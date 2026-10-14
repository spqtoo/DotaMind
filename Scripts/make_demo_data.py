#!/usr/bin/env python3
"""
Снимок ответов OpenDota и картинок для офлайн-демо приложения.

Запуск (из корня репозитория):
    python3 Scripts/make_demo_data.py [account_id] [--fresh]

Кладёт файлы в DotaMind/DemoData/. Приложение берёт их, когда сети нет
(см. DemoData.swift). Список запросов повторяет PlayerStore — если там
появится новый эндпоинт, добавь его сюда.
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
ACCOUNT = int(ARGS[0]) if ARGS else 1251170799
API = "https://api.opendota.com/api/"
CDN = "https://cdn.cloudflare.steamstatic.com"
OUT = os.path.join(os.path.dirname(__file__), "..", "DotaMind", "DemoData")

MODES = {
    "turbo": [("game_mode", "23"), ("significant", "0")],
    "normal": [],
    "all": [("significant", "0")],
}
HERO_DETAILS_PER_MODE = {"turbo": 10, "normal": 5, "all": 5}
RECORD_FIELDS = ["kills", "assists", "gold_per_min", "hero_damage", "last_hits", "duration"]  # = PlayerRecord.fields
MATCH_DETAILS = 8  # последних матчей с полной раскладкой (на режим)

manifest = {"api": {}, "images": {}}


def curl(url):
    # Тяжёлые запросы (totals по герою) OpenDota иногда считает дольше минуты.
    for attempt in range(4):
        out = subprocess.run(["curl", "-sfL", "--max-time", "120", url], capture_output=True)
        if out.returncode == 0:
            return out.stdout
        print(f"  повтор {attempt + 1} ({out.returncode}): {url}")
        time.sleep(5)
    raise RuntimeError(f"curl failed ({out.returncode}): {url}")


def key(path, query):
    """Совпадает с DemoData.key(for:) в Swift: путь после /api/ + отсортированные параметры."""
    q = "&".join(f"{k}={v}" for k, v in sorted(query))
    return path + ("?" + q if q else "")


def api(path, query=()):
    query = list(query)
    k = key(path, query)
    if k in manifest["api"]:
        return json.loads(open(os.path.join(OUT, manifest["api"][k])).read())
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = curl(url)
    name = f"demo_api_{len(manifest['api']):03d}.json"
    open(os.path.join(OUT, name), "wb").write(data)
    manifest["api"][k] = name
    save()
    print("api", k)
    time.sleep(1.1)  # лимит OpenDota без ключа ~60/мин
    return json.loads(data)


def image(url, as_jpeg):
    if not url or url in manifest["images"]:
        return
    ext = "jpg" if as_jpeg else "png"
    name = f"demo_img_{len(manifest['images']):03d}.{ext}"
    path = os.path.join(OUT, name)
    raw = path + ".raw"
    try:
        open(raw, "wb").write(curl(url))
    except RuntimeError as e:
        print("  пропуск картинки:", e)  # не критично: в приложении будет плейсхолдер
        return
    if as_jpeg:
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", raw, "--out", path],
                       capture_output=True, check=True)
        os.remove(raw)
    else:
        os.replace(raw, path)
    manifest["images"][url] = name
    save()


def save():
    json.dump(manifest, open(os.path.join(OUT, "demo_manifest.json"), "w"), indent=1, ensure_ascii=False)


def player_set(account, modes, hero_details, with_extras):
    """Все запросы PlayerStore для одного игрока. Возвращает id матчей для деталей."""
    p = f"players/{account}"
    player = api(p)
    match_ids = []
    for mode in modes:
        q = MODES[mode]
        api(f"{p}/wl", q)
        heroes = api(f"{p}/heroes", q)
        api(f"{p}/heroes", q + [("date", "30")])
        api(f"{p}/totals", q)
        api(f"{p}/counts", q)
        matches = api(f"{p}/matches", q + [("limit", "100")])
        match_ids += [m["match_id"] for m in matches[:MATCH_DETAILS]]
        peers = api(f"{p}/peers", q)
        for peer in peers[:10]:
            image(peer.get("avatarfull"), as_jpeg=True)
        if not with_extras:
            continue
        # Турбо-рейтинг: все Turbo-матчи с рангом лобби (= OpenDotaClient.turboHistory).
        if mode == "turbo":
            api(f"{p}/matches", q + [("project", "average_rank"), ("project", "start_time")])
        # Соло/пати (= loadExtras: wl с party_size 1…5).
        for size in range(1, 6):
            api(f"{p}/wl", q + [("party_size", str(size))])
        # Драфт для демо: враги Axe, Juggernaut, Pudge (= запуск с -DMDraft 2,8,14).
        if mode == "turbo":
            for enemy in (2, 8, 14):
                api(f"{p}/heroes", q + [("against_hero_id", str(enemy))])
        # Третий этап: форма и рекорды.
        api(f"{p}/matches", q + [("date", "84"), ("project", "start_time")])
        for field in RECORD_FIELDS:
            rec = api(f"{p}/matches", q + [("sort", field), ("limit", "1"), ("project", field),
                                           ("project", "hero_id"), ("project", "start_time")])
            match_ids += [m["match_id"] for m in rec]
        # Страницы героев.
        top = sorted((h for h in heroes if h["games"] > 0), key=lambda h: -h["games"])
        for h in top[:hero_details.get(mode, 0)]:
            hq = q + [("hero_id", str(h["hero_id"]))]
            api(f"{p}/totals", hq)
            hm = api(f"{p}/matches", hq + [("limit", "20")])
            match_ids += [m["match_id"] for m in hm[:2]]
            api(f"{p}/heroes", hq)
            api(f"{p}/matches", hq + [("limit", "100")] + [("project", f"item_{i}") for i in range(6)])
            if mode != "turbo":
                api("benchmarks", [("hero_id", str(h["hero_id"]))])
    image(player.get("profile", {}).get("avatarfull"), as_jpeg=True)
    tier = player.get("rank_tier") or 0
    if tier:
        medal, stars = tier // 10, tier % 10
        image(f"https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_{medal}.png", as_jpeg=False)
        if stars and medal < 8:
            image(f"https://www.opendota.com/assets/images/dota2/rank_icons/rank_star_{stars}.png", as_jpeg=False)
    return player, match_ids


def main():
    os.makedirs(OUT, exist_ok=True)
    # Повторный запуск докачивает недостающее; --fresh — собрать заново.
    path = os.path.join(OUT, "demo_manifest.json")
    if "--fresh" not in sys.argv and os.path.exists(path):
        manifest.update(json.load(open(path)))

    heroes_ref = api("heroStats")
    items = api("constants/items")
    item_img = {v["id"]: CDN + v["img"].split("?")[0] for k, v in items.items()
                if v.get("img") and not k.startswith("recipe_")}

    _, match_ids = player_set(ACCOUNT, list(MODES), HERO_DETAILS_PER_MODE, with_extras=True)

    # Друг для экрана сравнения — самый частый тиммейт в Turbo.
    peers = api(f"players/{ACCOUNT}/peers", MODES["turbo"])
    if peers:
        player_set(peers[0]["account_id"], ["turbo"], {}, with_extras=False)

    used_items = set()
    for mid in dict.fromkeys(match_ids):
        try:
            m = api(f"matches/{mid}")
        except RuntimeError as e:
            print("  пропуск матча:", e)
            continue
        for pl in m.get("players", []):
            used_items.update(pl.get(f"item_{i}") or 0 for i in range(6))
            used_items.add(pl.get("item_neutral") or 0)
    for key, name in list(manifest["api"].items()):
        if "project=item_0" in key:
            for row in json.load(open(os.path.join(OUT, name))):
                used_items.update(row.get(f"item_{i}") or 0 for i in range(6))
    for item_id in sorted(used_items - {0}):
        if item_id in item_img:
            image(item_img[item_id], as_jpeg=False)

    # Все медали и звёзды: турбо-ранг может отличаться от настоящего.
    for medal in range(1, 9):
        image(f"https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_{medal}.png", as_jpeg=False)
    for star in range(1, 6):
        image(f"https://www.opendota.com/assets/images/dota2/rank_icons/rank_star_{star}.png", as_jpeg=False)

    for h in heroes_ref:
        if h.get("img"):
            image(CDN + h["img"], as_jpeg=True)

    manifest["account_id"] = ACCOUNT
    manifest["created"] = int(time.time())
    save()
    print("готово:", len(manifest["api"]), "ответов,", len(manifest["images"]), "картинок")


if __name__ == "__main__":
    main()
