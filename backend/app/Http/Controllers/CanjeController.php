<?php

namespace App\Http\Controllers;

use App\Models\{Canje, PuntosLote, Recompensa};
use App\Services\PuntosService as P;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CanjeController extends Controller
{
    public function index(Request $r)
    {
        $q = Canje::latest('id');
        if ($r->user()->rol !== 'operador') {
            $q->where('user_id', $r->user()->id);
        }
        return $q->paginate(15);
    }

    public function store(Request $r)
    {
        $d = $r->validate(['recompensa_id' => 'required|integer|exists:recompensas,id']);
        $c = DB::transaction(function () use ($r, $d) {
            $rec = Recompensa::lockForUpdate()->findOrFail($d['recompensa_id']);
            abort_unless($rec->activa && $rec->stock > 0, 422, 'Recompensa no disponible');
            $lotes = P::consumir($r->user()->id, $rec->costo_puntos);
            abort_if($lotes === null, 422, 'Saldo insuficiente');
            $rec->decrement('stock');
            $c = Canje::create(['user_id' => $r->user()->id, 'recompensa_id' => $rec->id,
                'puntos' => $rec->costo_puntos, 'lotes' => $lotes]);
            P::evento('canje.solicitado', ['canje_id' => $c->id, 'user_id' => $c->user_id, 'puntos' => $c->puntos]);
            return $c;
        });
        return response()->json($c->fresh(), 201);
    }

    public function aprobar(int $id)
    {
        return $this->paso($id, ['solicitado'], 'aprobado');
    }

    public function entregar(int $id)
    {
        return $this->paso($id, ['aprobado'], 'entregado');
    }

    public function cancelar(int $id)
    {
        return $this->paso($id, ['solicitado', 'aprobado'], 'cancelado', function ($c) {
            foreach ($c->lotes ?? [] as $loteId => $n) {
                PuntosLote::whereKey($loteId)->increment('restantes', $n);
            }
            Recompensa::whereKey($c->recompensa_id)->increment('stock');
        });
    }

    private function paso(int $id, array $desde, string $hacia, ?callable $extra = null)
    {
        return DB::transaction(function () use ($id, $desde, $hacia, $extra) {
            $c = Canje::lockForUpdate()->findOrFail($id);
            abort_unless(in_array($c->estado, $desde, true), 409, "Transición inválida: '{$c->estado}' → '$hacia'");
            if ($extra) {
                $extra($c);
            }
            $c->update(['estado' => $hacia]);
            P::evento("canje.$hacia", ['canje_id' => $c->id, 'user_id' => $c->user_id, 'puntos' => $c->puntos]);
            return $c->fresh();
        });
    }
}
