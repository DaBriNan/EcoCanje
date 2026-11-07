<?php

use App\Http\Controllers\HealthController;
use App\Http\Middleware\Rol;
use Illuminate\Support\Facades\Route;

Route::get('/health/live', [HealthController::class, 'live']);
Route::get('/health/ready', [HealthController::class, 'ready']);
Route::middleware(['auth:sanctum', Rol::class . ':operador'])->get('/health/deps', [HealthController::class, 'deps']);
