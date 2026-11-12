<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Entrega extends Model
{
    protected $table = 'entregas';
    protected $guarded = ['id'];

    public function detalles()
    {
        return $this->hasMany(EntregaDetalle::class);
    }
}
