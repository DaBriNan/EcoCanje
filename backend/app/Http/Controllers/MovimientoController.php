<?php

namespace App\Http\Controllers;

use App\Models\Material;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class MovimientoController extends Controller
{
    private function col(string $nombre)
    {
        return DB::connection('mongodb')->getMongoDB()->selectCollection($nombre);
    }

    public function historial(Request $r)
    {
        $r->validate(['page' => 'nullable|integer|min:1', 'tipo' => 'nullable|string|max:40']);
        $filtro = $r->user()->rol === 'operador'
            ? ($r->filled('user_id') ? ['user_id' => (int) $r->input('user_id')] : [])
            : ['user_id' => $r->user()->id];
        if ($r->filled('tipo')) {
            $filtro['tipo'] = (string) $r->input('tipo');
        }
        $pag = max(1, (int) $r->input('page', 1));
        $n = 15;
        $col = $this->col('movimientos');
        $datos = $col->find($filtro, ['sort' => ['ocurrido_en' => -1], 'skip' => ($pag - 1) * $n, 'limit' => $n])->toArray();
        return ['pagina' => $pag, 'total' => $col->countDocuments($filtro), 'datos' => json_decode(json_encode($datos), true)];
    }

    public function fichaGet(int $id)
    {
        $doc = $this->col('fichas_material')->findOne(['_id' => $id]);
        abort_unless($doc, 404, 'El material no tiene ficha');
        return json_decode(json_encode($doc), true);
    }

    public function fichaPut(Request $r, int $id)
    {
        abort_unless(Material::whereKey($id)->exists(), 404, 'Material inexistente');
        $d = $r->validate(['atributos' => 'required|array|min:1|max:20', 'atributos.*' => 'nullable|string|max:100']);
        foreach (array_keys($d['atributos']) as $k) {
            abort_unless(preg_match('/^[a-z_]{1,40}$/', (string) $k), 422, "Clave de atributo inválida: $k");
        }
        $this->col('fichas_material')->updateOne(['_id' => $id], ['$set' => [
            'material_id' => $id, 'atributos' => $d['atributos'], 'actualizado_en' => now()->toIso8601String(),
        ]], ['upsert' => true]);
        return $this->fichaGet($id);
    }
}
