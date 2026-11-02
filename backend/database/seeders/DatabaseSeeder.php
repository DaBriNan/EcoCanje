<?php

namespace Database\Seeders;

use App\Models\{Entrega, EntregaDetalle, Material, PuntosLote, Recompensa, Tarifa, User};
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        if (User::exists()) { $this->command?->info("semilla ya aplicada"); return; }
        $pass = env('SEED_PASSWORD') ?: throw new \RuntimeException('Define SEED_PASSWORD en .env');
        $hash = Hash::make($pass);

        $op = User::forceCreate(['name' => 'Operador Demo', 'email' => 'operador@ecocanje.test', 'password' => $hash, 'rol' => 'operador']);
        $ciudadanos = collect(range(1, 30))->map(fn ($i) => User::forceCreate([
            'name' => "Ciudadano $i", 'email' => "ciudadano$i@ecocanje.test", 'password' => $hash, 'rol' => 'ciudadano',
        ]));

        $tarifas = collect();
        foreach (['PET' => 12, 'HDPE' => 10, 'Aluminio' => 30, 'Cartón' => 5, 'Papel' => 6, 'Vidrio' => 4, 'Acero' => 8, 'Tetra Pak' => 7] as $n => $ppk) {
            $m = Material::create(['nombre' => $n]);
            $tarifas->push(Tarifa::create(['material_id' => $m->id, 'puntos_por_kg' => $ppk, 'vigente_desde' => now()->subYear()]));
        }

        foreach ([
            ['Tarjeta de regalo $100', 'tarjeta_regalo', 100, 50], ['Tarjeta de regalo $200', 'tarjeta_regalo', 200, 40],
            ['Tarjeta de regalo $500', 'tarjeta_regalo', 500, 20], ['Vale de despensa $150', 'vale_despensa', 150, 40],
            ['Vale de despensa $300', 'vale_despensa', 300, 30], ['Vale de despensa $500', 'vale_despensa', 500, 20],
        ] as [$n, $t, $c, $s]) {
            Recompensa::create(['nombre' => $n, 'tipo' => $t, 'costo_puntos' => $c, 'stock' => $s]);
        }

        for ($i = 0; $i < 100; $i++) {
            $fecha = now()->subDays(rand(1, 90));
            $estado = $i < 80 ? 'acreditada' : ['rechazada', 'validada', 'pesada', 'registrada'][$i % 4];
            $e = Entrega::create([
                'user_id' => $ciudadanos->random()->id,
                'operador_id' => $estado === 'registrada' ? null : $op->id,
                'estado' => $estado,
                'motivo_rechazo' => $estado === 'rechazada' ? 'Material contaminado' : null,
                'created_at' => $fecha, 'updated_at' => $fecha,
            ]);
            $total = 0;
            foreach ($tarifas->random(rand(1, 3)) as $t) {
                $peso = rand(5, 50) / 10;
                $p = (int) round($peso * $t->puntos_por_kg);
                EntregaDetalle::create(['entrega_id' => $e->id, 'material_id' => $t->material_id, 'tarifa_id' => $t->id,
                    'peso_kg' => $peso, 'puntos' => $estado === 'acreditada' ? $p : 0]);
                $total += $p;
            }
            if ($estado === 'acreditada') {
                PuntosLote::create(['user_id' => $e->user_id, 'entrega_id' => $e->id, 'puntos' => $total,
                    'restantes' => $total, 'vence_en' => $fecha->copy()->addMonths(12), 'created_at' => $fecha, 'updated_at' => $fecha]);
            }
        }
    }
}
