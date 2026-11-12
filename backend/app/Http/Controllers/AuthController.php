<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    public function registro(Request $r)
    {
        $d = $r->validate([
            'name' => 'required|string|max:100',
            'email' => 'required|email|max:150|unique:users',
            'password' => 'required|string|min:10|max:100',
        ]);
        $u = User::forceCreate($d + ['rol' => 'ciudadano']);
        return response()->json(['token' => $u->createToken('api', ['*'], now()->addHours(8))->plainTextToken], 201);
    }

    public function login(Request $r)
    {
        $d = $r->validate(['email' => 'required|email', 'password' => 'required|string']);
        $u = User::where('email', $d['email'])->first();
        if (!$u || !Hash::check($d['password'], $u->password)) {
            return response()->json(['message' => 'Credenciales inválidas'], 401);
        }
        return ['token' => $u->createToken('api', ['*'], now()->addHours(8))->plainTextToken, 'rol' => $u->rol];
    }

    public function logout(Request $r)
    {
        $r->user()->currentAccessToken()->delete();
        return response()->noContent();
    }
}
