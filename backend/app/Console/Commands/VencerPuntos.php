<?php

namespace App\Console\Commands;

use App\Models\PuntosLote;
use App\Services\PuntosService as P;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class VencerPuntos extends Command
{
    protected $signature = 'puntos:vencer';
    protected $description = 'Da de baja los puntos vencidos y registra el evento';

    public function handle(): int
    {
        $n = 0;
        DB::transaction(function () use (&$n) {
            PuntosLote::where('vence_en', '<=', now())->where('restantes', '>', 0)->lockForUpdate()->get()
                ->each(function ($l) use (&$n) {
                    P::evento('puntos.vencidos', ['lote_id' => $l->id, 'user_id' => $l->user_id, 'puntos' => $l->restantes]);
                    $l->update(['restantes' => 0]);
                    $n++;
                });
        });
        $this->info("lotes vencidos=$n");
        return self::SUCCESS;
    }
}
