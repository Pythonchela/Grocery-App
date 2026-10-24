<?php

namespace App\Integrations;

/**
 * A set of related settings shown together: one integration, one card.
 */
final class Group
{
    /**
     * @param  list<Field>  $fields
     * @param  list<list<string>>  $together  field names that must be given as a set —
     *                                         all present or all absent (a login needs
     *                                         both its email and its password)
     * @param  array<string, array<string, list<string>>>  $requiredWhen  a choice field's name =>
     *                                         chosen value => the fields that choice needs
     *                                         (picking SMTP needs a host; picking the log
     *                                         mailer needs nothing)
     * @param  ?string  $tester  class name of the connection tester, if one exists
     * @param  list<list<string>>  $distinct  fields that must never hold the same value
     *                                         (the public and the private bucket)
     */
    public function __construct(
        public readonly string $id,
        public readonly string $label,
        public readonly string $description,
        public readonly array $fields,
        public readonly array $together = [],
        public readonly ?string $tester = null,
        public readonly array $requiredWhen = [],
        public readonly array $distinct = [],
    ) {}

    public function field(string $name): ?Field
    {
        foreach ($this->fields as $field) {
            if ($field->name === $name) {
                return $field;
            }
        }

        return null;
    }
}
