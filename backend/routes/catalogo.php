<?php

use App\Http\Controllers\{MaterialController, MovimientoController, RecompensaController};
use App\Http\Middleware\Rol;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/historial', [MovimientoController::class, 'historial']);
    Route::get('/materiales/{id}/ficha', [MovimientoController::class, 'fichaGet']);
    Route::middleware(Rol::class . ':operador')->group(function () {
        Route::put('/materiales/{id}/ficha', [MovimientoController::class, 'fichaPut']);
        Route::post('/materiales', [MaterialController::class, 'store']);
        Route::put('/materiales/{id}', [MaterialController::class, 'update']);
        Route::delete('/materiales/{id}', [MaterialController::class, 'destroy']);
        Route::post('/materiales/{id}/tarifas', [MaterialController::class, 'tarifa']);
        Route::post('/recompensas', [RecompensaController::class, 'store']);
        Route::put('/recompensas/{id}', [RecompensaController::class, 'update']);
        Route::delete('/recompensas/{id}', [RecompensaController::class, 'destroy']);
    });
});
