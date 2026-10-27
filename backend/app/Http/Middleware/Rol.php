<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class Rol
{
    public function handle(Request $request, Closure $next, string $rol)
    {
        abort_unless($request->user()?->rol === $rol, 403, 'No autorizado');
        return $next($request);
    }
}
