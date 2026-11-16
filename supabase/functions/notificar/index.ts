// Envía las notificaciones push de Bitácora de Inmuebles.
// GET  -> devuelve la clave pública con la que cada dispositivo se suscribe.
// POST -> lo llama la base de datos (trigger) cuando alguien del equipo guarda algo.
import { createClient } from "npm:@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush@0.5.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function claveAdmin(): string {
  try {
    const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (typeof k.default === "string") return k.default;
    const primera = Object.values(k)[0];
    if (typeof primera === "string") return primera;
  } catch (_) { /* sigue con la clave heredada */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, claveAdmin(), {
  auth: { persistSession: false, autoRefreshToken: false },
});

let servidor: webpush.ApplicationServer | null = null;
let clavePublica = "";

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function leerConfig() {
  const { data, error } = await db.from("push_config").select("secreto, vapid").eq("id", 1).maybeSingle();
  if (error) throw new Error("push_config: " + error.message);
  if (!data) throw new Error("push_config sin fila");
  return data as { secreto: string; vapid: webpush.ExportedVapidKeys | null };
}

// Las claves VAPID se generan aquí la primera vez y quedan guardadas en la base.
async function preparar() {
  if (servidor) return;
  let cfg = await leerConfig();
  if (!cfg.vapid) {
    const nuevas = await webpush.generateVapidKeys({ extractable: true });
    const exportadas = await webpush.exportVapidKeys(nuevas);
    const { error } = await db.from("push_config").update({ vapid: exportadas }).eq("id", 1).is("vapid", null);
    if (error) throw new Error("guardar claves: " + error.message);
    cfg = await leerConfig();
  }
  if (!cfg.vapid) throw new Error("no se pudieron guardar las claves");
  const claves = await webpush.importVapidKeys(cfg.vapid, { extractable: false });
  clavePublica = await webpush.exportApplicationServerKey(claves);
  servidor = await webpush.ApplicationServer.new({
    contactInformation: "https://camipou-ctrl.github.io/Bitacora-inmuebles/",
    vapidKeys: claves,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    await preparar();
    if (req.method === "GET") return json({ clave: clavePublica });
    if (req.method !== "POST") return json({ error: "método no permitido" }, 405);

    const cfg = await leerConfig();
    if (!cfg.secreto || req.headers.get("x-bitacora-secreto") !== cfg.secreto) {
      return json({ error: "no autorizado" }, 401);
    }

    const b = await req.json();
    const actor = String(b.actor ?? "");
    if (!actor) return json({ enviadas: 0, motivo: "sin autor" });

    const { data: perfil } = await db.from("perfiles").select("nombre").eq("user_id", actor).maybeSingle();
    const nombre = perfil?.nombre ?? "Alguien del equipo";
    const que = b.tabla === "inmuebles" ? "un inmueble" : "una atención";
    const verbo = b.tipo === "INSERT" ? "registró" : b.tipo === "DELETE" ? "eliminó" : "editó";
    const mensaje = JSON.stringify({
      title: `${nombre} ${verbo} ${que}`,
      body: String(b.titulo ?? "").slice(0, 120),
      tag: String(b.tabla ?? "bitacora"),
      url: "./",
    });

    const { data: subs, error } = await db
      .from("suscripciones_push")
      .select("endpoint, p256dh, auth")
      .neq("user_id", actor);
    if (error) throw new Error("suscripciones: " + error.message);

    let enviadas = 0, caducadas = 0, fallidas = 0;
    for (const s of subs ?? []) {
      try {
        const suscriptor = servidor!.subscribe({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } });
        // deno-lint-ignore no-explicit-any
        await suscriptor.pushTextMessage(mensaje, {} as any);
        enviadas++;
      } catch (e) {
        if (e instanceof webpush.PushMessageError && e.isGone()) {
          caducadas++;
          await db.from("suscripciones_push").delete().eq("endpoint", s.endpoint);
        } else {
          fallidas++;
          console.error("push fallido:", String(e));
        }
      }
    }
    return json({ enviadas, caducadas, fallidas });
  } catch (e) {
    console.error("notificar:", String(e));
    return json({ error: String(e) }, 500);
  }
});
