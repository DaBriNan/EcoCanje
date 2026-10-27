<?php

namespace App\Console\Commands;

use App\Models\Outbox;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class PublicarOutbox extends Command
{
    protected $signature = 'outbox:publicar {--loop : repetir cada 2 segundos}';
    protected $description = 'Publica eventos pendientes del outbox en MongoDB de forma idempotente';

    public function handle(): int
    {
        do {
            [$ok, $error] = $this->lote();
            $this->info("publicados=$ok" . ($error ? " error=$error" : ''));
            if ($this->option('loop')) {
                sleep(2);
            }
        } while ($this->option('loop'));
        return $error ? self::FAILURE : self::SUCCESS;
    }

    private function lote(): array
    {
        $ok = 0;
        $error = null;
        DB::transaction(function () use (&$ok, &$error) {
            $col = DB::connection('mongodb')->getMongoDB()->selectCollection('movimientos');
            $pend = Outbox::whereNull('publicado_en')->orderBy('created_at')->orderBy('id')
                ->limit(100)->lock('for update skip locked')->get();
            foreach ($pend as $o) {
                try {
                    // _id = id del outbox: reintentar nunca duplica el documento
                    $col->updateOne(['_id' => $o->id], ['$setOnInsert' => [
                        'tipo' => $o->tipo,
                        'user_id' => (int) ($o->payload['user_id'] ?? 0),
                        'ocurrido_en' => $o->payload['ocurrido_en'],
                        'payload' => $o->payload,
                    ]], ['upsert' => true]);
                    $o->update(['publicado_en' => now()]);
                    $ok++;
                } catch (\Throwable $e) {
                    $o->increment('intentos');
                    $error = class_basename($e);
                    break; // conserva el orden y evita esperar el timeout por cada evento
                }
            }
        });
        return [$ok, $error];
    }
}
