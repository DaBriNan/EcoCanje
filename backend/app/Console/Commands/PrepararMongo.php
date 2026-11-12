<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class PrepararMongo extends Command
{
    protected $signature = 'mongo:preparar';
    protected $description = 'Crea colecciones con validación e índices (idempotente)';

    public function handle(): int
    {
        $db = DB::connection('mongodb')->getMongoDB();
        $existentes = iterator_to_array($db->listCollectionNames());
        $defs = [
            'movimientos' => ['required' => ['tipo', 'user_id', 'ocurrido_en', 'payload'], 'properties' => [
                'tipo' => ['bsonType' => 'string'], 'user_id' => ['bsonType' => ['int', 'long']],
                'ocurrido_en' => ['bsonType' => 'string'], 'payload' => ['bsonType' => 'object']]],
            'fichas_material' => ['required' => ['material_id', 'atributos'], 'properties' => [
                'material_id' => ['bsonType' => ['int', 'long']], 'atributos' => ['bsonType' => 'object']]],
        ];
        foreach ($defs as $nombre => $schema) {
            $validator = ['$jsonSchema' => ['bsonType' => 'object'] + $schema];
            if (!in_array($nombre, $existentes, true)) {
                $db->createCollection($nombre, ['validator' => $validator, 'validationAction' => 'error']);
            } else {
                $db->command(['collMod' => $nombre, 'validator' => $validator]);
            }
        }
        $mov = $db->selectCollection('movimientos');
        $mov->createIndex(['user_id' => 1, 'ocurrido_en' => -1]);
        $mov->createIndex(['tipo' => 1]);
        $this->info('MongoDB listo');
        return self::SUCCESS;
    }
}
