<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;

/**
 * Gives an admin a password, from the server's command line.
 *
 * Changing integration credentials asks the admin to confirm with their password.
 * An admin who signed up through Google or an OTP has none, and the admin panel
 * rightly will not let them create one while signed in — a stolen session could
 * otherwise set its own password and then use it. Server access is the trusted
 * route, so this is it.
 *
 *     php artisan haatvia:set-password ops@shop.in
 *
 * The password is prompted for, never passed as an argument, so it stays out of
 * shell history and the process list.
 */
class SetAdminPassword extends Command
{
    protected $signature = 'haatvia:set-password {email : The admin account\'s email address}';

    protected $description = 'Set or reset the password of an admin account';

    public function handle(): int
    {
        $email = strtolower(trim((string) $this->argument('email')));
        $user = User::whereRaw('LOWER(email) = ?', [$email])->first();

        if (! $user || ! $user->isAdmin()) {
            // One message for both, so this cannot be used to find out who exists.
            $this->error('No admin account with that email.');

            return self::FAILURE;
        }

        $password = (string) $this->secret('New password (min. 10 characters)');
        $confirm = (string) $this->secret('Repeat the password');

        if ($password !== $confirm) {
            $this->error('The two passwords do not match.');

            return self::FAILURE;
        }

        $check = Validator::make(['password' => $password], ['password' => 'required|string|min:10|max:128']);

        if ($check->fails()) {
            $this->error($check->errors()->first('password'));

            return self::FAILURE;
        }

        $user->forceFill(['password' => Hash::make($password)])->save();

        // Sessions signed in before the reset should not survive it.
        $user->tokens()->delete();

        $this->info("Password set for {$user->email}. Their other sessions were signed out.");

        return self::SUCCESS;
    }
}
