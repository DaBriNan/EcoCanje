<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', fn (Blueprint $t) => $t->string('rol', 20)->default('ciudadano'));
        Schema::create('materiales', function (Blueprint $t) {
            $t->id(); $t->string('nombre', 80)->unique(); $t->boolean('activo')->default(true); $t->timestamps();
        });
        Schema::create('tarifas', function (Blueprint $t) {
            $t->id(); $t->foreignId('material_id')->constrained('materiales');
            $t->unsignedInteger('puntos_por_kg'); $t->timestamp('vigente_desde'); $t->timestamps();
            $t->index(['material_id', 'vigente_desde']);
        });
        Schema::create('entregas', function (Blueprint $t) {
            $t->id(); $t->foreignId('user_id')->constrained(); $t->foreignId('operador_id')->nullable()->constrained('users');
            $t->string('estado', 20)->default('registrada'); $t->string('motivo_rechazo')->nullable(); $t->timestamps();
            $t->index(['user_id', 'estado']);
        });
        Schema::create('entrega_detalles', function (Blueprint $t) {
            $t->id(); $t->foreignId('entrega_id')->constrained()->cascadeOnDelete();
            $t->foreignId('material_id')->constrained('materiales'); $t->foreignId('tarifa_id')->constrained('tarifas');
            $t->decimal('peso_kg', 8, 2); $t->unsignedInteger('puntos')->default(0);
        });
        Schema::create('recompensas', function (Blueprint $t) {
            $t->id(); $t->string('nombre', 100); $t->string('tipo', 20);
            $t->unsignedInteger('costo_puntos'); $t->unsignedInteger('stock'); $t->boolean('activa')->default(true); $t->timestamps();
        });
        Schema::create('canjes', function (Blueprint $t) {
            $t->id(); $t->foreignId('user_id')->constrained(); $t->foreignId('recompensa_id')->constrained('recompensas');
            $t->unsignedInteger('puntos'); $t->string('estado', 20)->default('solicitado'); $t->timestamps();
            $t->index(['user_id', 'estado']);
        });
        Schema::create('puntos_lotes', function (Blueprint $t) {
            $t->id(); $t->foreignId('user_id')->constrained(); $t->foreignId('entrega_id')->constrained();
            $t->unsignedInteger('puntos'); $t->unsignedInteger('restantes'); $t->timestamp('vence_en'); $t->timestamps();
            $t->index(['user_id', 'vence_en']);
        });
        Schema::create('outbox', function (Blueprint $t) {
            $t->uuid('id')->primary(); $t->string('tipo', 40); $t->json('payload');
            $t->timestamp('publicado_en')->nullable(); $t->unsignedSmallInteger('intentos')->default(0); $t->timestamps();
            $t->index('publicado_en');
        });
        foreach ([
            "users ADD CONSTRAINT chk_rol CHECK (rol IN ('ciudadano','operador'))",
            "entregas ADD CONSTRAINT chk_ent_estado CHECK (estado IN ('registrada','pesada','validada','acreditada','rechazada'))",
            "canjes ADD CONSTRAINT chk_canje_estado CHECK (estado IN ('solicitado','aprobado','entregado','cancelado'))",
            "recompensas ADD CONSTRAINT chk_tipo CHECK (tipo IN ('tarjeta_regalo','vale_despensa'))",
            "entrega_detalles ADD CONSTRAINT chk_peso CHECK (peso_kg > 0)",
        ] as $sql) {
            DB::statement("ALTER TABLE $sql");
        }
    }

    public function down(): void
    {
        foreach (['outbox', 'puntos_lotes', 'canjes', 'recompensas', 'entrega_detalles', 'entregas', 'tarifas', 'materiales'] as $t) {
            Schema::dropIfExists($t);
        }
        Schema::table('users', fn (Blueprint $t) => $t->dropColumn('rol'));
    }
};
