<?php

namespace App\Http\Controllers;

use App\Models\{Canje, Material, PuntosLote, Recompensa, Tarifa};
use App\Services\PuntosService as P;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class CatalogoController extends Controller
{
    public function materiales()
    {
        // Una sola consulta para la tarifa vigente de cada material (antes una consulta por material, N+1)
        $tarifas = Tarifa::query()->selectRaw('distinct on (material_id) material_id, puntos_por_kg')
            ->where('vigente_desde', '<=', now())->orderBy('material_id')->orderByDesc('vigente_desde')->orderByDesc('id')
            ->pluck('puntos_por_kg', 'material_id');
        return Material::where('activo', true)->orderBy('nombre')->get()->map(fn ($m) => [
            'id' => $m->id,
            'nombre' => $m->nombre,
            'puntos_por_kg' => $tarifas[$m->id] ?? null,
        ]);
    }

    public function recompensas()
    {
        return Recompensa::where('activa', true)->where('stock', '>', 0)->orderBy('costo_puntos')->get();
    }

    public function saldo(Request $r)
    {
        $u = $r->user()->id;
        return [
            'saldo' => P::saldo($u),
            'vence_en_30_dias' => (int) PuntosLote::where('user_id', $u)->whereBetween('vence_en', [now(), now()->addDays(30)])->sum('restantes'),
            'tope_diario_restante' => max(0, P::TOPE_DIARIO - P::acreditadoHoy($u)),
        ];
    }

    public function reporte(Request $r)
    {
        $d = $r->validate(['mes' => 'nullable|date_format:Y-m']);
        $ini = Carbon::createFromFormat('Y-m-d', ($d['mes'] ?? now()->format('Y-m')) . '-01')->startOfDay();
        $fin = $ini->copy()->addMonth();

        $porMaterial = DB::table('entrega_detalles as d')
            ->join('entregas as e', 'e.id', '=', 'd.entrega_id')
            ->join('materiales as m', 'm.id', '=', 'd.material_id')
            ->where('e.estado', 'acreditada')->where('e.created_at', '>=', $ini)->where('e.created_at', '<', $fin)
            ->groupBy('m.nombre')->orderByDesc('kilos')
            ->selectRaw('m.nombre, sum(d.peso_kg) as kilos, sum(d.puntos) as puntos')->get();

        return [
            'mes' => $ini->format('Y-m'),
            'por_material' => $porMaterial,
            'puntos_otorgados' => (int) PuntosLote::where('created_at', '>=', $ini)->where('created_at', '<', $fin)->sum('puntos'),
            'puntos_canjeados' => (int) Canje::where('estado', '!=', 'cancelado')
                ->where('created_at', '>=', $ini)->where('created_at', '<', $fin)->sum('puntos'),
        ];
    }
}
