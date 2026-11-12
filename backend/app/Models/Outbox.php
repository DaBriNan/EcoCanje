<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Outbox extends Model
{
    use HasUuids;

    protected $table = 'outbox';
    protected $guarded = [];
    protected $casts = ['payload' => 'array', 'publicado_en' => 'datetime'];
}
