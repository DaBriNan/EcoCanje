<?php

use App\Http\Controllers\{AuthController, CanjeController, CatalogoController, EntregaController};
use App\Http\Middleware\Rol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::post('/registro', [AuthController::class, 'registro'])->middleware('throttle:10,1');
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:5,1');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/yo', fn (Request $r) => $r->user());

    Route::get('/materiales', [CatalogoController::class, 'materiales']);
    Route::get('/recompensas', [CatalogoController::class, 'recompensas']);
    Route::get('/saldo', [CatalogoController::class, 'saldo']);
    Route::get('/entregas', [EntregaController::class, 'index']);
    Route::get('/canjes', [CanjeController::class, 'index']);
    Route::post('/canjes', [CanjeController::class, 'store'])->middleware(Rol::class . ':ciudadano');

    Route::middleware(Rol::class . ':operador')->group(function () {
        Route::get('/operador/ping', fn () => ['ok' => true]);
        Route::post('/entregas', [EntregaController::class, 'store']);
        Route::patch('/entregas/{id}/pesar', [EntregaController::class, 'pesar']);
        Route::patch('/entregas/{id}/validar', [EntregaController::class, 'validar']);
        Route::patch('/entregas/{id}/rechazar', [EntregaController::class, 'rechazar']);
        Route::patch('/entregas/{id}/acreditar', [EntregaController::class, 'acreditar']);
        Route::patch('/canjes/{id}/aprobar', [CanjeController::class, 'aprobar']);
        Route::patch('/canjes/{id}/entregar', [CanjeController::class, 'entregar']);
        Route::patch('/canjes/{id}/cancelar', [CanjeController::class, 'cancelar']);
        Route::get('/reportes/mensual', [CatalogoController::class, 'reporte']);
    });
});
require __DIR__ . '/catalogo.php';
