<?php

namespace App\Http\Controllers;

use App\Models\Recompensa;
use Illuminate\Http\Request;

class RecompensaController extends Controller
{
    public function store(Request $r)
    {
        $d = $r->validate([
            'nombre' => 'required|string|max:100',
            'tipo' => 'required|in:tarjeta_regalo,vale_despensa',
            'costo_puntos' => 'required|integer|min:1|max:100000',
            'stock' => 'required|integer|min:0|max:100000',
        ]);
        return response()->json(Recompensa::create($d)->fresh(), 201);
    }

    public function update(Request $r, int $id)
    {
        $m = Recompensa::findOrFail($id);
        $m->update($r->validate([
            'nombre' => 'sometimes|string|max:100',
            'tipo' => 'sometimes|in:tarjeta_regalo,vale_despensa',
            'costo_puntos' => 'sometimes|integer|min:1|max:100000',
            'stock' => 'sometimes|integer|min:0|max:100000',
            'activa' => 'sometimes|boolean',
        ]));
        return $m->fresh();
    }

    public function destroy(int $id)
    {
        Recompensa::findOrFail($id)->update(['activa' => false]);
        return response()->noContent();
    }
}
