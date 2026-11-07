<?php

namespace App\Http\Controllers;

use App\Models\{Material, Tarifa};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class MaterialController extends Controller
{
    public function store(Request $r)
    {
        $d = $r->validate(['nombre' => 'required|string|max:80|unique:materiales,nombre', 'puntos_por_kg' => 'required|integer|min:1|max:1000']);
        $m = DB::transaction(function () use ($d) {
            $m = Material::create(['nombre' => $d['nombre']]);
            Tarifa::create(['material_id' => $m->id, 'puntos_por_kg' => $d['puntos_por_kg'], 'vigente_desde' => now()]);
            return $m;
        });
        return response()->json($m->fresh(), 201);
    }

    public function update(Request $r, int $id)
    {
        $m = Material::findOrFail($id);
        $d = $r->validate([
            'nombre' => ['sometimes', 'string', 'max:80', Rule::unique('materiales', 'nombre')->ignore($m->id)],
            'activo' => 'sometimes|boolean',
        ]);
        $m->update($d);
        return $m->fresh();
    }

    public function destroy(int $id)
    {
        Material::findOrFail($id)->update(['activo' => false]); // baja lógica: conserva el historial de entregas
        return response()->noContent();
    }

    public function tarifa(Request $r, int $id)
    {
        Material::findOrFail($id);
        $d = $r->validate(['puntos_por_kg' => 'required|integer|min:1|max:1000']);
        return response()->json(Tarifa::create(['material_id' => $id, 'puntos_por_kg' => $d['puntos_por_kg'], 'vigente_desde' => now()]), 201);
    }
}
