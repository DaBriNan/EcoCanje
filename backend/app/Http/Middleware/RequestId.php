<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

// Correlación: nginx genera o propaga X-Request-Id y lo devuelve al cliente; aquí se agrega a todo log de la solicitud
// y queda disponible para guardarlo en los eventos del outbox (de ahí al log del worker y al documento en MongoDB).
class RequestId
{
    public function handle(Request $request, Closure $next): Response
    {
        $id = $request->headers->get('X-Request-Id');
        if (!is_string($id) || !preg_match('/^[A-Za-z0-9._-]{8,64}$/', $id)) {
            $id = (string) Str::uuid();
        }
        app()->instance('request_id', $id);
        Log::withContext(['request_id' => $id]);
        return $next($request);
    }
}
