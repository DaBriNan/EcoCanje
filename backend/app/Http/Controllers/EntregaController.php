<?php

namespace App\Http\Controllers;

use App\Models\{Entrega, EntregaDetalle, Material, PuntosLote, Tarifa, User};
use App\Services\PuntosService as P;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class EntregaController extends Controller
{
    public function index(Request $r)
    {
        $q = Entrega::with('detalles')->latest('id');
        if ($r->user()->rol !== 'operador') {
            $q->where('user_id', $r->user()->id);
        } elseif ($r->filled('user_id')) {
            $q->where('user_id', (int) $r->input('user_id'));
        }
        if ($r->filled('estado')) {
            $q->where('estado', (string) $r->input('estado'));
        }
        return $q->paginate(15);
    }

    public function store(Request $r)
    {
        $d = $r->validate([
            'user_id' => 'required|integer|exists:users,id',
            'detalles' => 'required|array|min:1|max:10',
            'detalles.*.material_id' => 'required|integer|distinct|exists:materiales,id',
            'detalles.*.peso_kg' => 'required|numeric|min:0.1|max:200',
        ]);
        abort_unless(User::whereKey($d['user_id'])->where('rol', 'ciudadano')->exists(), 422, 'El usuario no es ciudadano');

        $e = DB::transaction(function () use ($r, $d) {
            $e = Entrega::create(['user_id' => $d['user_id'], 'operador_id' => $r->user()->id]);
            foreach ($d['detalles'] as $x) {
                abort_unless(Material::whereKey($x['material_id'])->where('activo', true)->exists(), 422, 'Material inactivo');
                $t = Tarifa::where('material_id', $x['material_id'])->where('vigente_desde', '<=', now())
                    ->orderByDesc('vigente_desde')->first();
                abort_unless($t, 422, 'Material sin tarifa vigente');
                EntregaDetalle::create(['entrega_id' => $e->id, 'material_id' => $x['material_id'],
                    'tarifa_id' => $t->id, 'peso_kg' => $x['peso_kg']]);
            }
            P::evento('entrega.registrada', ['entrega_id' => $e->id, 'user_id' => $e->user_id]);
            return $e;
        });
        return response()->json($e->fresh('detalles'), 201);
    }

    public function pesar(Request $r, int $id)
    {
        $d = $r->validate([
            'detalles' => 'required|array|min:1',
            'detalles.*.id' => 'required|integer|distinct',
            'detalles.*.peso_kg' => 'required|numeric|min:0.1|max:200',
        ]);
        return $this->paso($id, ['registrada'], 'pesada', function ($e) use ($d) {
            foreach ($d['detalles'] as $x) {
                $n = EntregaDetalle::where('entrega_id', $e->id)->whereKey($x['id'])->update(['peso_kg' => $x['peso_kg']]);
                abort_unless($n === 1, 422, "El detalle {$x['id']} no pertenece a la entrega");
            }
        });
    }

    public function validar(int $id)
    {
        return $this->paso($id, ['pesada'], 'validada');
    }

    public function rechazar(Request $r, int $id)
    {
        $d = $r->validate(['motivo' => 'required|string|max:200']);
        return $this->paso($id, ['registrada', 'pesada', 'validada'], 'rechazada', function ($e) use ($d) {
            $e->motivo_rechazo = $d['motivo'];
        });
    }

    public function acreditar(int $id)
    {
        return $this->paso($id, ['validada'], 'acreditada', function ($e) {
            User::lockForUpdate()->findOrFail($e->user_id); // serializa acreditaciones de la misma persona
            $det = EntregaDetalle::where('entrega_id', $e->id)->get();
            $tarifas = Tarifa::whereIn('id', $det->pluck('tarifa_id'))->get()->keyBy('id');
            $total = 0;
            foreach ($det as $x) {
                $p = (int) round($x->peso_kg * $tarifas[$x->tarifa_id]->puntos_por_kg);
                $x->update(['puntos' => $p]);
                $total += $p;
            }
            abort_if($total < 1, 422, 'La entrega no genera puntos');
            abort_if(P::acreditadoHoy($e->user_id) + $total > P::TOPE_DIARIO, 422,
                'Tope diario de ' . P::TOPE_DIARIO . ' puntos excedido');
            PuntosLote::create(['user_id' => $e->user_id, 'entrega_id' => $e->id, 'puntos' => $total,
                'restantes' => $total, 'vence_en' => now()->addMonths(P::VIGENCIA_MESES)]);
            return ['puntos' => $total];
        });
    }

    private function paso(int $id, array $desde, string $hacia, ?callable $extra = null)
    {
        return DB::transaction(function () use ($id, $desde, $hacia, $extra) {
            $e = Entrega::lockForUpdate()->findOrFail($id);
            abort_unless(in_array($e->estado, $desde, true), 409, "Transición inválida: '{$e->estado}' → '$hacia'");
            $x = $extra ? $extra($e) : null;
            $e->update(['estado' => $hacia]);
            P::evento("entrega.$hacia", ['entrega_id' => $e->id, 'user_id' => $e->user_id] + (is_array($x) ? $x : []));
            return $e->fresh('detalles');
        });
    }
}
