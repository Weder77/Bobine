"""Fake Xtream Codes server for end-to-end testing of Lumen (supports HTTP Range)."""
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
BASE = f"http://127.0.0.1:{PORT}"
MEDIA = os.path.join(ROOT, "media")
IMG = os.path.join(ROOT, "img")
# Throttle VOD to ~3 MB/s so cache behaviour is visible.
RATE = int(os.environ.get("RATE", "3000000"))

CHANNELS = [
    ("TF1 HD", "tf1.fr", "1"), ("France 2 HD", "france2.fr", "1"), ("Sport Max", "sportmax", "2"),
    ("Ciné Nuit", "cinenuit", "3"), ("Arte", "arte.fr", "1"), ("M6 HD", "m6.fr", "1"),
    ("News 24", "news24", "4"), ("Kids TV", "kids", "5"),
]
MOVIE_TITLES = ["Horizon", "Le Phare", "Nuit Blanche", "Odyssée", "Brume", "Atlas",
                "Orbite", "Marée", "Vertige", "Solstice", "Rivage", "Éclipse"]
PROGRAMS = ["Journal de 20h", "Météo", "Le grand match", "Documentaire : Océans", "Série du soir",
            "Talk-show", "Cinéma : Horizon", "Magazine auto", "Dessins animés", "Info en continu"]


def tmdb(path, q, headers):
    """Tiny stand-in for The Movie Database (LUMEN_TMDB_BASE=http://127.0.0.1:8765/tmdb/3)."""
    key = q.get("api_key", [""])[0] or headers.get("Authorization", "").replace("Bearer ", "")
    if key != "testkey":
        return 401, {"status_message": "Invalid API key"}
    if path == "/configuration":
        return 200, {"images": {}}
    m = re.match(r"^/search/(movie|tv)$", path)
    if m:
        query = q.get("query", [""])[0].lower()
        titles = MOVIE_TITLES if m.group(1) == "movie" else ["Les Veilleurs", "Atlas", "Rivage"]
        hits = [{"id": 1000 + i, "title": t, "name": t} for i, t in enumerate(titles) if t.lower() == query]
        return 200, {"results": hits}
    m = re.match(r"^/(movie|tv)/(\d+)$", path)
    if m:
        i = int(m.group(2)) - 1000
        tv = m.group(1) == "tv"
        return 200, {
            "id": int(m.group(2)), "title": None if tv else MOVIE_TITLES[i % 12], "name": "Série" if tv else None,
            "overview": "Résumé TMDB : au bord d'un monde qui s'efface, une équipe tente de sauver ce qui peut "
                        "l'être. Un film de test servi par le faux TMDB de Lumen.",
            "tagline": "Chaque lumière a son ombre.",
            "backdrop_path": f"/backdrop{(i + 3) % 12}.png", "poster_path": f"/poster{i % 12}.png",
            "genres": [{"name": "Science-Fiction"}, {"name": "Aventure"}],
            "vote_average": 7.8, "release_date": f"{2015 + i}-03-01", "first_air_date": "2021-09-10",
            "runtime": 128, "episode_run_time": [42],
            "credits": {"cast": [{"name": "Léa Fontaine"}, {"name": "Marc Aubry"}, {"name": "Inès Roche"}],
                        "crew": [{"job": "Director", "name": "Paul Vernier"}]},
            "created_by": [{"name": "Nora Lemaire"}],
            "videos": {"results": [{"site": "YouTube", "type": "Trailer", "key": "dQw4w9WgXcQ", "iso_639_1": "fr"}]},
        }
    return 404, {"status_message": "not found"}


def api(action, q):
    if action is None:
        return {"user_info": {"username": "demo", "auth": 1, "status": "Active",
                              "exp_date": str(int(time.time()) + 86400 * 200),
                              "is_trial": "0", "active_cons": "0", "max_connections": "2",
                              "allowed_output_formats": ["m3u8", "ts"]},
                "server_info": {"url": "127.0.0.1", "port": str(PORT)}}
    if action == "get_live_categories":
        return [{"category_id": "1", "category_name": "France"}, {"category_id": "2", "category_name": "Sport"},
                {"category_id": "3", "category_name": "Cinéma"}, {"category_id": "4", "category_name": "Info"},
                {"category_id": "5", "category_name": "Jeunesse"}]
    if action == "get_live_streams":
        return [{"num": i + 1, "name": n, "stream_type": "live", "stream_id": 100 + i,
                 "stream_icon": f"{BASE}/img/logo{i}.png", "epg_channel_id": epg,
                 "category_id": cat, "tv_archive": 1 if i < 2 else 0, "tv_archive_duration": 7}
                for i, (n, epg, cat) in enumerate(CHANNELS)]
    if action == "get_vod_categories":
        return [{"category_id": "10", "category_name": "Action"}, {"category_id": "11", "category_name": "Drame"}]
    if action == "get_vod_streams":
        return [{"num": i + 1, "name": f"{t} ({2015 + i})", "stream_id": 500 + i,
                 "stream_icon": f"{BASE}/img/poster{i}.png", "rating": str(6 + (i % 4) * 0.8),
                 "added": str(int(time.time()) - i * 86400), "category_id": "10" if i % 2 else "11",
                 "container_extension": "mkv"} for i, t in enumerate(MOVIE_TITLES)]
    if action == "get_vod_info":
        i = int(q.get("vod_id", ["500"])[0]) - 500
        return {"info": {"movie_image": f"{BASE}/img/poster{i}.png",
                         "backdrop_path": [f"{BASE}/img/backdrop{i}.png"],
                         "plot": "Un récit visuel généré pour tester Lumen : deux pistes audio (VF / VO), "
                                 "des sous-titres et un cache de lecture agressif pour des sauts instantanés.",
                         "cast": "Alice Martin, Bruno Leroy", "director": "Claire Dubois",
                         "genre": "Drame, Aventure", "releasedate": f"{2015 + i}-05-12",
                         "duration_secs": 300, "rating": "7.4"},
                "movie_data": {"stream_id": 500 + i, "container_extension": "mkv"}}
    if action == "get_series_categories":
        return [{"category_id": "20", "category_name": "Séries FR"}]
    if action == "get_series":
        return [{"num": i + 1, "name": n, "series_id": 900 + i, "cover": f"{BASE}/img/poster{(i + 5) % 12}.png",
                 "plot": "Une série de test.", "genre": "Thriller", "releaseDate": f"{2019 + i}-01-01",
                 "last_modified": str(int(time.time()) - i * 3600), "rating": "8.1", "category_id": "20",
                 "backdrop_path": [f"{BASE}/img/backdrop{(i + 5) % 12}.png"]}
                for i, n in enumerate(["Les Veilleurs", "Code Ambre", "Station 9"])]
    if action == "get_series_info":
        sid = q.get("series_id", ["900"])[0]
        eps = {}
        for s in (1, 2):
            eps[str(s)] = [{"id": f"{sid}{s}{e:02d}", "episode_num": e, "season": s,
                            "title": f"Épisode {e} : {['Le départ', 'La nuit', 'Le retour', 'Le choix'][e - 1]}",
                            "container_extension": "mp4",
                            "info": {"duration_secs": 120, "plot": "Résumé de l'épisode pour le test.",
                                     "movie_image": f"{BASE}/img/backdrop{(e + s) % 12}.png"}}
                           for e in range(1, 5)]
        return {"seasons": [], "info": {"name": "Série", "plot": "Une série de test avec deux saisons.",
                                        "cast": "Equipe de test", "genre": "Thriller",
                                        "backdrop_path": [f"{BASE}/img/backdrop7.png"], "rating": "8.1"},
                "episodes": eps}
    if action == "get_short_epg":
        return {"epg_listings": []}
    return []


def xmltv():
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0) - timedelta(hours=3)
    out = ['<?xml version="1.0" encoding="UTF-8"?>\n<tv>']
    for n, epg, _ in CHANNELS:
        out.append(f'<channel id="{epg}"><display-name>{n}</display-name></channel>')
    for ci, (n, epg, _) in enumerate(CHANNELS):
        t = now
        k = ci
        while t < now + timedelta(days=2):
            dur = timedelta(minutes=[30, 45, 60, 90][k % 4])
            fmt = "%Y%m%d%H%M%S +0000"
            title = PROGRAMS[k % len(PROGRAMS)].replace("&", "&amp;")
            out.append(f'<programme start="{t.strftime(fmt)}" stop="{(t + dur).strftime(fmt)}" channel="{epg}">'
                       f'<title lang="fr">{title}</title><desc lang="fr">Description de « {title} » '
                       f'sur {n}.</desc></programme>')
            t += dur
            k += 1
    out.append("</tv>")
    return "\n".join(out).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        if os.environ.get("VERBOSE"):
            sys.stderr.write(fmt % args + "\n")

    def send_bytes(self, data, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_file(self, path, ctype, throttle=False):
        size = os.path.getsize(path)
        start, end = 0, size - 1
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = int(m.group(2))
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else:
            self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            chunk = 64 * 1024
            t0 = time.time()
            sent = 0
            try:
                while remaining > 0:
                    data = f.read(min(chunk, remaining))
                    if not data:
                        break
                    self.wfile.write(data)
                    remaining -= len(data)
                    sent += len(data)
                    if throttle:
                        ahead = sent / RATE - (time.time() - t0)
                        if ahead > 0:
                            time.sleep(ahead)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        if p == "/player_api.php":
            return self.send_bytes(json.dumps(api(q.get("action", [None])[0], q)).encode(), "application/json")
        if p == "/xmltv.php":
            return self.send_bytes(xmltv(), "application/xml")
        if p == "/gh/releases/latest":
            # Fake GitHub release (LUMEN_UPDATE_URL=http://127.0.0.1:8765/gh/releases/latest).
            return self.send_bytes(json.dumps({
                "tag_name": "v1.2.0", "html_url": "https://github.com/weder77/iptv/releases/tag/v1.2.0",
                "body": "- Multi-écran\n- Corrections diverses",
                "assets": [{"name": "Lumen-Setup-1.2.0.exe", "size": 4, "digest": "sha256:00",
                            "browser_download_url": f"{BASE}/gh/setup.exe"}]}).encode(), "application/json")
        if p.startswith("/tmdb/3/"):
            code, body = tmdb(p[len("/tmdb/3"):], q, self.headers)
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if p.startswith("/tmdb/img/"):
            f = os.path.join(IMG, os.path.basename(p))
            if os.path.exists(f):
                return self.serve_file(f, "image/png")
        if p.startswith("/img/"):
            f = os.path.join(IMG, os.path.basename(p))
            if os.path.exists(f):
                return self.serve_file(f, "image/png")
        if p.startswith("/live/"):
            return self.serve_file(os.path.join(MEDIA, "live.ts"), "video/mp2t")
        if p.startswith("/timeshift/"):
            # Replay of a past programme: served like a film (seekable).
            print("timeshift", p, flush=True)
            return self.serve_file(os.path.join(MEDIA, "movie.mkv"), "video/x-matroska", throttle=True)
        if p.startswith("/movie/"):
            return self.serve_file(os.path.join(MEDIA, "movie.mkv"), "video/x-matroska", throttle=True)
        if p.startswith("/series/"):
            return self.serve_file(os.path.join(MEDIA, "episode.mp4"), "video/mp4", throttle=True)
        self.send_bytes(b"not found", "text/plain")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
