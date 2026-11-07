<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class EntregaDetalle extends Model
{
    protected $table = 'entrega_detalles';
    public $timestamps = false;
    protected $guarded = ['id'];
}
