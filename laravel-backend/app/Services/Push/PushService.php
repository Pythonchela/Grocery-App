<?php

namespace App\Services\Push;

use App\Models\DeviceToken;
use App\Models\User;

/**
 * Delivers one notification to every phone a user has signed in on.
 *
 * Best effort by design: push is an extra channel on top of the in-app
 * notification that is always stored, so a push that cannot be sent is dropped
 * quietly rather than failing the order or refund that caused it.
 */
class PushService
{
    public function __construct(private readonly FcmClient $fcm) {}

    public function enabled(): bool
    {
        return $this->fcm->configured();
    }

    /**
     * @param  array<string, mixed>  $data
     * @return int how many devices accepted the message
     */
    public function notify(User $user, string $title, ?string $body = null, array $data = []): int
    {
        if (! $this->fcm->configured()) {
            return 0;
        }

        $delivered = 0;

        foreach (DeviceToken::where('user_id', $user->id)->get() as $device) {
            $result = $this->fcm->send($device->token, $title, $body, $data);

            if ($result === 'sent') {
                $delivered++;
            } elseif ($result === 'invalid_token') {
                // The app was removed or reinstalled; stop paying for dead ends.
                $device->delete();
            }
        }

        return $delivered;
    }
}
