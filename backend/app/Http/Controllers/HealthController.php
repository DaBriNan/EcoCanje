<?php

namespace App\Http\Controllers;

use App\Models\Outbox;
use Illuminate\Support\Facades\DB;

class HealthController extends Controller
{
    public function live()
    {
        return ['status' => 'ok'];
    }

    public function ready()
    {
        try {
            DB::select('select 1');
        } catch (\Throwable) {
            return response()->json(['status' => 'postgres_no_disponible'], 503);
        }
        return ['status' => 'ok'];
    }

    public function deps()
    {
        $pg = $mongo = 'ok';
        try {
            DB::select('select 1');
        } catch (\Throwable) {
            $pg = 'caido';
        }
        try {
            DB::connection('mongodb')->getMongoDB()->command(['ping' => 1]);
        } catch (\Throwable) {
            $mongo = 'caido';
        }
        return response()->json([
            'postgres' => $pg,
            'mongodb' => $mongo,
            'outbox_pendientes' => $pg === 'ok' ? Outbox::whereNull('publicado_en')->count() : null,
        ], ($pg === 'ok' && $mongo === 'ok') ? 200 : 503);
    }
}
