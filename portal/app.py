"""Portail ClashRetro : comptes, rôles, invitations, appairage des appareils, administration.

Le serveur de jeu ne fait que lire `devices`/`accounts` (AccessGate.cs) ; tout ce qui écrit
passe par ici. Schéma : db/init/02_portal.sql.
"""
import csv
import base64
import functools
import glob
import hashlib
import hmac
import io
import json
import os
import secrets
from collections import defaultdict
from datetime import datetime, timedelta

import pymysql
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from flask import Flask, Response, abort, flash, g, redirect, render_template, request, session, url_for

# Secrets dans des fichiers (VAR_FILE, ex. /data/secrets/…) quand ils ne sont pas donnés directement.
for _var in ("MYSQL_PASSWORD", "PORTAL_SECRET"):
    if not os.environ.get(_var) and os.environ.get(_var + "_FILE"):
        with open(os.environ[_var + "_FILE"], encoding="utf-8") as _f:
            os.environ[_var] = _f.read().strip()

app = Flask(__name__)
app.secret_key = os.environ["PORTAL_SECRET"]
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax",
                  SESSION_COOKIE_SECURE=os.environ.get("PORTAL_SECURE_COOKIE", "false") == "true")

hasher = PasswordHasher()
INVITE_DAYS = int(os.environ.get("INVITE_VALID_DAYS", "14"))
BATTLE_LOG_DIR = os.environ.get("BATTLE_LOG_DIR", "/logs/battles")
with open(os.path.join(os.path.dirname(__file__), "cards.json"), encoding="utf-8") as _f:
    CARDS = json.load(_f)
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def db():
    if "db" not in g:
        g.db = pymysql.connect(host=os.environ.get("MYSQL_HOST", "db"), user=os.environ["MYSQL_USER"],
                               password=os.environ["MYSQL_PASSWORD"], database=os.environ["MYSQL_DATABASE"],
                               charset="utf8mb4", cursorclass=pymysql.cursors.DictCursor, autocommit=False)
    return g.db


@app.teardown_appcontext
def close_db(_):
    conn = g.pop("db", None)
    if conn:
        conn.close()


def ensure_schema():
    """Mise à niveau des bases créées avant l'ajout de game_jobs (db/init/03_jobs.sql)."""
    try:
        with open(os.path.join(os.path.dirname(__file__), "03_jobs.sql"), encoding="utf-8") as f:
            sql = f.read()
        conn = pymysql.connect(host=os.environ.get("MYSQL_HOST", "db"), user=os.environ["MYSQL_USER"],
                               password=os.environ["MYSQL_PASSWORD"], database=os.environ["MYSQL_DATABASE"])
        with conn.cursor() as cur:
            for statement in sql.split(";"):
                code = "\n".join(l for l in statement.splitlines() if not l.strip().startswith("--")).strip()
                if code:
                    cur.execute(code)
        conn.commit()
        conn.close()
    except Exception as e:  # base pas encore prête : le script d'init s'en chargera
        print("ensure_schema:", e)


ensure_schema()


def query(sql, args=(), one=False):
    with db().cursor() as cur:
        cur.execute(sql, args)
        rows = cur.fetchall()
    return (rows[0] if rows else None) if one else rows


def execute(sql, args=()):
    with db().cursor() as cur:
        cur.execute(sql, args)
        return cur.lastrowid


def audit(action, target=None, **details):
    execute("INSERT INTO audit_log (actor_id, action, target, details) VALUES (%s, %s, %s, %s)",
            (session.get("uid"), action, target, json.dumps(details) if details else None))


def current_user():
    if "uid" not in session:
        return None
    if "user" not in g:
        g.user = query("SELECT a.*, r.name AS role, r.can_admin FROM accounts a JOIN roles r ON r.id = a.role_id "
                       "WHERE a.id = %s AND a.disabled_at IS NULL", (session["uid"],), one=True)
    return g.user


def login_required(view):
    @functools.wraps(view)
    def wrapped(*args, **kwargs):
        if not current_user():
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapped


def admin_required(view):
    @functools.wraps(view)
    @login_required
    def wrapped(*args, **kwargs):
        if not current_user()["can_admin"]:
            abort(403)
        return view(*args, **kwargs)
    return wrapped


@app.before_request
def csrf_protect():
    if request.method == "POST":
        token = session.get("csrf")
        if not token or token != request.form.get("csrf"):
            abort(400, "jeton CSRF invalide")


@app.context_processor
def inject():
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return {"user": current_user(), "csrf": session["csrf"]}


PBKDF2_ITERATIONS = 210000


def hash_password(password):
    """Même format que le serveur de jeu (Core/Accounts.cs) : un compte sert au jeu et au portail."""
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ITERATIONS, 32)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password, stored):
    if stored.startswith("pbkdf2_sha256$"):
        _, iterations, salt, digest = stored.split("$")
        expected = base64.b64decode(digest)
        got = hashlib.pbkdf2_hmac("sha256", password.encode(), base64.b64decode(salt), int(iterations), len(expected))
        return hmac.compare_digest(got, expected)
    try:
        return hasher.verify(stored, password)   # anciens comptes argon2id
    except VerifyMismatchError:
        return False


def random_code(length=12):
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(length))


# --- Authentification -------------------------------------------------------------------------

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        user = query("SELECT id, password_hash FROM accounts WHERE username = %s AND disabled_at IS NULL",
                     (request.form["username"].strip(),), one=True)
        if user and verify_password(request.form["password"], user["password_hash"]):
            if not user["password_hash"].startswith("pbkdf2_sha256$"):
                # Ancien hachage argon2 : converti pour que le même compte serve aussi dans le jeu.
                execute("UPDATE accounts SET password_hash = %s WHERE id = %s",
                        (hash_password(request.form["password"]), user["id"]))
                db().commit()
            session.clear()
            session["uid"] = user["id"]
            target = request.args.get("next", "")
            return redirect(target if target.startswith("/") and not target.startswith("//") else url_for("home"))
        flash("Identifiants invalides.")
    return render_template("login.html")


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/register", methods=["GET", "POST"])
def register():
    code = request.values.get("code", "").strip().upper()
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        if not (3 <= len(username) <= 32) or len(password) < 10:
            flash("Pseudo de 3 à 32 caractères, mot de passe de 10 caractères minimum.")
            return render_template("register.html", code=code)
        invite = query("SELECT * FROM invitations WHERE code = %s AND used_by IS NULL AND revoked_at IS NULL "
                       "AND expires_at > UTC_TIMESTAMP() FOR UPDATE", (code,), one=True)
        if not invite:
            db().rollback()
            flash("Invitation invalide, expirée ou déjà utilisée.")
            return render_template("register.html", code=code)
        if query("SELECT 1 FROM accounts WHERE username = %s", (username,), one=True):
            db().rollback()
            flash("Pseudo déjà pris.")
            return render_template("register.html", code=code)
        uid = execute("INSERT INTO accounts (username, password_hash, role_id, invited_by) VALUES (%s, %s, %s, %s)",
                      (username, hash_password(password), invite["role_id"], invite["created_by"]))
        execute("UPDATE invitations SET used_by = %s, used_at = UTC_TIMESTAMP() WHERE id = %s", (uid, invite["id"]))
        session.clear()
        session["uid"] = uid
        audit("account.register", username, invitation=invite["id"])
        db().commit()
        return redirect(url_for("home"))
    return render_template("register.html", code=code)


# --- Combat amical (QR code affiché par le client) ---------------------------------------------

@app.get("/a/<code>")
def friendly(code):
    # Page publique : ne lit ni n'écrit rien, elle copie le code et ouvre l'appli.
    if not code.isascii() or not code.isalnum() or len(code) != 6:
        abort(404)
    return render_template("friendly.html", code=code.upper())


# --- Espace joueur ----------------------------------------------------------------------------

@app.get("/")
@login_required
def home():
    uid = current_user()["id"]
    return render_template(
        "home.html",
        quota=query("SELECT * FROM v_invite_quota WHERE account_id = %s", (uid,), one=True),
        invitations=query("SELECT i.*, a.username AS used_by_name FROM invitations i "
                          "LEFT JOIN accounts a ON a.id = i.used_by WHERE i.created_by = %s "
                          "ORDER BY i.created_at DESC", (uid,)),
        devices=query("SELECT * FROM v_player_progress WHERE account_id = %s", (uid,)),
        pending=query("SELECT id, platform, device_model, pairing_code FROM devices "
                      "WHERE account_id = %s AND status = 'approved' AND player_id IS NULL", (uid,)),
    )


@app.post("/pair")
@login_required
def pair():
    code = request.form["pairing_code"].strip().upper()
    if len(code) == 8:
        code = f"{code[:4]}-{code[4:]}"
    device = query("SELECT * FROM devices WHERE pairing_code = %s AND status = 'pending' FOR UPDATE", (code,), one=True)
    if not device:
        db().rollback()
        flash("Code d'appairage inconnu. Lance le jeu pour en obtenir un.")
        return redirect(url_for("home"))
    execute("UPDATE devices SET status = 'approved', account_id = %s, approved_at = UTC_TIMESTAMP() WHERE id = %s",
            (current_user()["id"], device["id"]))
    audit("device.approve", code, platform=device["platform"])
    db().commit()
    flash("Appareil approuvé : relance le jeu.")
    return redirect(url_for("home"))


@app.post("/invitations")
@login_required
def create_invitation():
    user = current_user()
    query("SELECT id FROM accounts WHERE id = %s FOR UPDATE", (user["id"],))  # sérialise les créations
    quota = query("SELECT * FROM v_invite_quota WHERE account_id = %s", (user["id"],), one=True)
    if quota["remaining"] is not None and quota["remaining"] <= 0:
        flash("Quota d'invitations atteint.")
        return redirect(url_for("home"))
    role_name = request.form.get("role", "invite") if user["can_admin"] else "invite"
    role = query("SELECT id FROM roles WHERE name = %s", (role_name,), one=True) or abort(400)
    code = random_code()
    execute("INSERT INTO invitations (code, created_by, role_id, note, expires_at) VALUES (%s, %s, %s, %s, %s)",
            (code, user["id"], role["id"], request.form.get("note", "")[:128] or None,
             datetime.utcnow() + timedelta(days=INVITE_DAYS)))
    audit("invitation.create", code, role=role_name)
    db().commit()
    flash(f"Invitation créée : {url_for('register', code=code, _external=True)}")
    return redirect(url_for("home"))


@app.post("/invitations/<int:invite_id>/revoke")
@login_required
def revoke_invitation(invite_id):
    user = current_user()
    owner_clause = "" if user["can_admin"] else " AND created_by = %s"
    args = (invite_id,) if user["can_admin"] else (invite_id, user["id"])
    execute("UPDATE invitations SET revoked_at = UTC_TIMESTAMP() WHERE id = %s AND used_by IS NULL" + owner_clause, args)
    audit("invitation.revoke", str(invite_id))
    db().commit()
    return redirect(request.referrer or url_for("home"))


# --- Mes données (export, effacement) ---------------------------------------------------------

def my_player_ids(uid):
    return [r["player_id"] for r in query("SELECT player_id FROM devices WHERE account_id = %s "
                                          "AND player_id IS NOT NULL", (uid,))]


@app.get("/me/export")
@login_required
def export_my_data():
    """Tout ce que le serveur garde sur l'utilisateur, en JSON lisible."""
    user = current_user()
    players = []
    for pid in my_player_ids(user["id"]):
        row = query("SELECT Id, Home FROM player WHERE Id = %s", (pid,), one=True)
        if row:
            players.append({"player_id": row["Id"], "game_data": json.loads(row["Home"])})
    data = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "account": query("SELECT username, created_at, disabled_at FROM accounts WHERE id = %s", (user["id"],), one=True),
        "role": user["role"],
        "devices": query("SELECT platform, device_model, status, created_at, approved_at, last_seen_at, player_id "
                         "FROM devices WHERE account_id = %s", (user["id"],)),
        "invitations_created": query("SELECT code, note, created_at, expires_at, used_at, revoked_at "
                                     "FROM invitations WHERE created_by = %s", (user["id"],)),
        "players": players,
        "battle_logs": "anonymes (identifiant haché salé), non reliables à ce compte ; conservation limitée",
    }
    audit("privacy.export", str(user["id"]))
    db().commit()
    body = json.dumps(data, ensure_ascii=False, indent=2, default=str)
    return Response(body, mimetype="application/json",
                    headers={"Content-Disposition": f"attachment; filename=clashretro-{user['username']}.json"})


@app.post("/me/delete")
@login_required
def delete_my_data():
    """Effacement : joueurs supprimés par le serveur de jeu, appareils et invitations effacés,
    compte anonymisé (le journal d'audit ne garde que l'identifiant numérique)."""
    user = current_user()
    row = query("SELECT password_hash FROM accounts WHERE id = %s", (user["id"],), one=True)
    if not verify_password(request.form.get("password", ""), row["password_hash"]):
        flash("Mot de passe incorrect : rien n'a été supprimé.")
        return redirect(url_for("home"))
    if user["can_admin"] and query("SELECT COUNT(*) AS n FROM accounts a JOIN roles r ON r.id = a.role_id "
                                   "WHERE r.can_admin AND a.disabled_at IS NULL", one=True)["n"] <= 1:
        flash("Dernier admin : nomme un autre admin avant de supprimer ton compte.")
        return redirect(url_for("home"))
    for pid in my_player_ids(user["id"]):
        execute("INSERT INTO game_jobs (kind, player_id, created_by) VALUES ('delete_player', %s, %s)",
                (pid, user["id"]))
    execute("DELETE FROM devices WHERE account_id = %s", (user["id"],))
    execute("DELETE FROM invitations WHERE created_by = %s AND used_by IS NULL", (user["id"],))
    execute("UPDATE invitations SET note = NULL WHERE created_by = %s", (user["id"],))
    execute("UPDATE accounts SET username = %s, password_hash = '!', disabled_at = UTC_TIMESTAMP() WHERE id = %s",
            (f"supprime-{user['id']}", user["id"]))
    audit("privacy.delete", str(user["id"]))
    db().commit()
    session.clear()
    flash("Compte supprimé. Les données de jeu sont effacées par le serveur dans la minute.")
    return redirect(url_for("login"))


# --- Administration ---------------------------------------------------------------------------

@app.get("/admin")
@admin_required
def admin():
    return render_template(
        "admin.html",
        roles=query("SELECT * FROM roles ORDER BY id"),
        users=query("SELECT a.id, a.username, a.role_id, a.invite_quota_override, a.disabled_at, a.created_at, "
                    "q.used, q.remaining, inv.username AS invited_by_name FROM accounts a "
                    "JOIN v_invite_quota q ON q.account_id = a.id "
                    "LEFT JOIN accounts inv ON inv.id = a.invited_by ORDER BY a.id"),
        devices=query("SELECT d.*, a.username FROM devices d LEFT JOIN accounts a ON a.id = d.account_id "
                      "ORDER BY d.last_seen_at DESC LIMIT 200"),
        progress=query("SELECT * FROM v_player_progress ORDER BY trophies DESC LIMIT 200"),
        jobs=query("SELECT j.*, a.username FROM game_jobs j LEFT JOIN accounts a ON a.id = j.created_by "
                   "ORDER BY j.id DESC LIMIT 20"),
        events=query("SELECT *, (starts_at <= UTC_TIMESTAMP() AND ends_at > UTC_TIMESTAMP()) AS active "
                     "FROM events ORDER BY starts_at DESC LIMIT 30"),
        audit=query("SELECT l.*, a.username FROM audit_log l LEFT JOIN accounts a ON a.id = l.actor_id "
                    "ORDER BY l.id DESC LIMIT 50"),
    )


def optional_int(value):
    return int(value) if value not in (None, "") else None


@app.post("/admin/roles/<int:role_id>")
@admin_required
def admin_role(role_id):
    execute("UPDATE roles SET invite_quota = %s WHERE id = %s", (optional_int(request.form.get("invite_quota")), role_id))
    audit("role.quota", str(role_id), quota=request.form.get("invite_quota"))
    db().commit()
    return redirect(url_for("admin"))


@app.post("/admin/users/<int:user_id>")
@admin_required
def admin_user(user_id):
    if user_id == current_user()["id"] and request.form.get("action") == "disable":
        abort(400, "impossible de se désactiver soi-même")
    action = request.form.get("action")
    if action == "disable":
        execute("UPDATE accounts SET disabled_at = UTC_TIMESTAMP() WHERE id = %s", (user_id,))
    elif action == "enable":
        execute("UPDATE accounts SET disabled_at = NULL WHERE id = %s", (user_id,))
    else:
        execute("UPDATE accounts SET role_id = %s, invite_quota_override = %s WHERE id = %s",
                (int(request.form["role_id"]), optional_int(request.form.get("quota_override")), user_id))
    audit(f"account.{action or 'update'}", str(user_id), **{k: v for k, v in request.form.items() if k != "csrf"})
    db().commit()
    return redirect(url_for("admin"))


@app.post("/admin/devices/<int:device_id>")
@admin_required
def admin_device(device_id):
    action = request.form.get("action")
    if action == "revoke":
        execute("UPDATE devices SET status = 'revoked' WHERE id = %s", (device_id,))
    elif action == "reset":
        # L'appareil pourra recréer un compte neuf ; l'ancien joueur reste en base.
        execute("DELETE FROM devices WHERE id = %s", (device_id,))
    else:
        abort(400)
    audit(f"device.{action}", str(device_id))
    db().commit()
    return redirect(url_for("admin"))


@app.post("/admin/players/<int:player_id>/grant")
@admin_required
def admin_grant(player_id):
    gold = max(0, min(1_000_000, optional_int(request.form.get("gold")) or 0))
    gems = max(0, min(1_000_000, optional_int(request.form.get("gems")) or 0))
    execute("INSERT INTO game_jobs (kind, player_id, payload, created_by) VALUES ('grant', %s, %s, %s)",
            (player_id, json.dumps({"gold": gold, "gems": gems}), current_user()["id"]))
    audit("player.grant", str(player_id), gold=gold, gems=gems)
    db().commit()
    flash(f"Don programmé : +{gold} or, +{gems} gemmes (appliqué dans les 30 s).")
    return redirect(url_for("admin"))


@app.post("/admin/events")
@admin_required
def admin_event_create():
    """Évènement temporaire : bonus d'or / de cartes sur les coffres et annonce dans le jeu."""
    f = request.form
    try:
        starts = datetime.fromisoformat(f["starts_at"]) if f.get("starts_at") else datetime.utcnow()
        ends = datetime.fromisoformat(f["ends_at"])
        gold = min(100.0, max(0.1, float(f.get("gold_multiplier") or 1)))
        cards = min(100.0, max(0.1, float(f.get("card_multiplier") or 1)))
    except (KeyError, ValueError):
        flash("Dates ou multiplicateurs invalides.")
        return redirect(url_for("admin"))
    if ends <= starts:
        flash("La fin doit être après le début.")
        return redirect(url_for("admin"))
    execute("INSERT INTO events (title, message, starts_at, ends_at, gold_multiplier, card_multiplier, created_by) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s)",
            (f.get("title", "Évènement")[:64], (f.get("message") or "")[:255] or None, starts, ends, gold, cards,
             current_user()["id"]))
    audit("event.create", f.get("title", "")[:64], gold=gold, cards=cards)
    db().commit()
    flash("Évènement programmé (pris en compte par le jeu dans les 30 s).")
    return redirect(url_for("admin"))


@app.post("/admin/events/<int:event_id>/delete")
@admin_required
def admin_event_delete(event_id):
    execute("DELETE FROM events WHERE id = %s", (event_id,))
    audit("event.delete", str(event_id))
    db().commit()
    return redirect(url_for("admin"))


# --- Combats : statistiques anonymes pour l'équilibrage ---------------------------------------

def battle_entries():
    for path in sorted(glob.glob(os.path.join(BATTLE_LOG_DIR, "battles-*.jsonl"))):
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue


def card_stats():
    """Par carte : présence dans les decks, victoires, taux de victoire, poses, niveau moyen."""
    stats = defaultdict(lambda: {"decks": 0, "wins": 0, "losses": 0, "plays": 0, "level_sum": 0})
    battles = draws = disagreements = 0
    for b in battle_entries():
        battles += 1
        if not b.get("agree", True):
            disagreements += 1
        if b.get("winner", -1) < 0:
            draws += 1
        for i, player in enumerate(b.get("players", [])):
            for card in player.get("deck", []):
                s = stats[str(card.get("card"))]
                s["decks"] += 1
                s["level_sum"] += card.get("level", 0)
                if b.get("winner", -1) == i:
                    s["wins"] += 1
                elif b.get("winner", -1) >= 0:
                    s["losses"] += 1
        for p in b.get("placements", []):
            stats[str(p.get("card"))]["plays"] += 1
    rows = []
    for card_id, s in stats.items():
        info = CARDS.get(card_id, {"name": card_id, "rarity": "", "elixir": ""})
        decided = s["wins"] + s["losses"]
        rows.append({"card": card_id, "name": info["name"], "rarity": info["rarity"], "elixir": info["elixir"],
                     "decks": s["decks"], "plays": s["plays"], "wins": s["wins"], "losses": s["losses"],
                     "win_rate": round(100 * s["wins"] / decided, 1) if decided else None,
                     "avg_level": round(s["level_sum"] / s["decks"] + 1, 1) if s["decks"] else None})
    rows.sort(key=lambda r: -r["decks"])
    return {"battles": battles, "draws": draws, "disagreements": disagreements}, rows


@app.get("/admin/battles")
@admin_required
def admin_battles():
    summary, rows = card_stats()
    return render_template("battles.html", summary=summary, rows=rows, log_dir=BATTLE_LOG_DIR)


@app.get("/admin/battles.csv")
@admin_required
def admin_battles_csv():
    _, rows = card_stats()
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=["card", "name", "rarity", "elixir", "decks", "plays", "wins",
                                             "losses", "win_rate", "avg_level"])
    writer.writeheader()
    writer.writerows(rows)
    return Response(out.getvalue(), mimetype="text/csv",
                    headers={"Content-Disposition": "attachment; filename=clashretro-cartes.csv"})


@app.get("/admin/battles.jsonl")
@admin_required
def admin_battles_raw():
    """Journal brut (déjà anonymisé) pour une analyse par IA."""
    def lines():
        for path in sorted(glob.glob(os.path.join(BATTLE_LOG_DIR, "battles-*.jsonl"))):
            with open(path, encoding="utf-8") as f:
                yield from f
    return Response(lines(), mimetype="application/x-ndjson",
                    headers={"Content-Disposition": "attachment; filename=clashretro-combats.jsonl"})


# --- Amorçage ---------------------------------------------------------------------------------

@app.cli.command("create-admin")
def create_admin():
    """Crée le premier compte admin (mot de passe demandé de façon interactive)."""
    import click
    username = click.prompt("Pseudo admin")
    password = click.prompt("Mot de passe", hide_input=True, confirmation_prompt=True)
    execute("INSERT INTO accounts (username, password_hash, role_id) "
            "SELECT %s, %s, id FROM roles WHERE name = 'admin'", (username, hash_password(password)))
    db().commit()
    click.echo(f"Admin {username} créé.")
