<?php

use App\Http\Controllers\AuthController;
use App\Http\Middleware\Rol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::post('/registro', [AuthController::class, 'registro'])->middleware('throttle:10,1');
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:5,1');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/yo', fn (Request $r) => $r->user());
    Route::middleware(Rol::class . ':operador')->get('/operador/ping', fn () => ['ok' => true]);
});
