<?php

namespace App\Services;

use App\Models\{Outbox, PuntosLote};

class PuntosService
{
    public const TOPE_DIARIO = 500;
    public const VIGENCIA_MESES = 12;

    public static function saldo(int $userId): int
    {
        return (int) PuntosLote::where('user_id', $userId)->where('vence_en', '>', now())->sum('restantes');
    }

    public static function acreditadoHoy(int $userId): int
    {
        return (int) PuntosLote::where('user_id', $userId)->where('created_at', '>=', now()->startOfDay())->sum('puntos');
    }

    /** Consume FIFO por vencimiento. Llamar dentro de una transacción. Devuelve [lote_id => puntos] o null si no alcanza. */
    public static function consumir(int $userId, int $puntos): ?array
    {
        $lotes = PuntosLote::where('user_id', $userId)->where('vence_en', '>', now())->where('restantes', '>', 0)
            ->orderBy('vence_en')->lockForUpdate()->get();
        if ($lotes->sum('restantes') < $puntos) {
            return null;
        }
        $usados = [];
        foreach ($lotes as $l) {
            if ($puntos <= 0) {
                break;
            }
            $t = min($l->restantes, $puntos);
            $l->decrement('restantes', $t);
            $usados[$l->id] = $t;
            $puntos -= $t;
        }
        return $usados;
    }

    public static function evento(string $tipo, array $payload): void
    {
        $rid = app()->bound('request_id') ? app('request_id') : null;
        $o = Outbox::create(['tipo' => $tipo, 'payload' => $payload + ['ocurrido_en' => now()->toIso8601String(), 'request_id' => $rid]]);
        \Illuminate\Support\Facades\Log::info('evento registrado', ['outbox_id' => $o->id, 'tipo' => $tipo]);
    }
}
