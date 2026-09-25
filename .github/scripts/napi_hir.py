# Napi hírösszesítő: a nap közben a hirek_varolista.json-ba gyűjtött híreket éjfél után
# (budapesti idő szerint) egyetlen napi bejegyzésként teszi ki a docs/hirek.json elejére –
# ezt olvassa a honlap és a launcher. A mai (még tartó) nap tételei a várólistán maradnak.
#
# A várólista tételei ugyanolyanok, mint a hirek.json bejegyzései:
#   {"datum": "2026-09-25", "cim": ..., "cimke": ..., "szoveg": ..., "cim_en": ..., "szoveg_en": ...,
#    "cim_de": ..., "szoveg_de": ..., "cimke_en": ..., "cimke_de": ...}
# Kézi indításnál (KENYSZER=1) a mai tételek is kikerülnek.

import datetime
import json
import os
import zoneinfo

GYOKER = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VAROLISTA = os.path.join(GYOKER, "hirek_varolista.json")
HIREK = os.path.join(GYOKER, "docs", "hirek.json")

CIM_ELO = {"": "A nap frissítései", "_en": "Today's updates", "_de": "Updates des Tages"}


def beolvas(ut):
    with open(ut, "rb") as f:
        adat = f.read()
    bom = adat.startswith(b"\xef\xbb\xbf")
    return json.loads(adat.decode("utf-8-sig")), bom


def kiir(ut, ertek, bom):
    szoveg = json.dumps(ertek, ensure_ascii=False, indent="\t") + "\n"
    with open(ut, "wb") as f:
        if bom:
            f.write(b"\xef\xbb\xbf")
        f.write(szoveg.encode("utf-8"))


def budapesti_ma():
    try:
        return datetime.datetime.now(zoneinfo.ZoneInfo("Europe/Budapest")).date()
    except Exception:
        # időzóna-adatbázis nélkül (pl. Windows): közép-európai idő, nyári időszámítás március utolsó
        # vasárnapjától október utolsó vasárnapjáig (01:00 UTC-kor vált)
        most = datetime.datetime.now(datetime.timezone.utc)
        def utolso_vasarnap(ho):
            nap = datetime.datetime(most.year, ho, 31, 1, tzinfo=datetime.timezone.utc)
            return nap - datetime.timedelta(days=(nap.weekday() + 1) % 7)
        nyari = utolso_vasarnap(3) <= most < utolso_vasarnap(10)
        return (most + datetime.timedelta(hours=2 if nyari else 1)).date()


def rovid_cim(cim):
    # "Heptarchia 1.66 – festett díszsávok" → "Heptarchia 1.66"
    return cim.split(" – ")[0].strip()


def osszefuz(datum, tetelek):
    if len(tetelek) == 1:
        return dict(tetelek[0], datum=datum)
    uj = {"datum": datum}
    for nyelv in ("", "_en", "_de"):
        cimek = [t.get("cim" + nyelv) or t.get("cim", "") for t in tetelek]
        uj["cim" + nyelv] = CIM_ELO[nyelv] + ": " + ", ".join(dict.fromkeys(rovid_cim(c) for c in cimek))
        reszek = []
        for t in tetelek:
            cim = t.get("cim" + nyelv) or t.get("cim", "")
            szov = t.get("szoveg" + nyelv) or t.get("szoveg", "")
            reszek.append("▸ " + cim + "\n" + szov)
        uj["szoveg" + nyelv] = "\n\n".join(reszek)
    cimkek = list(dict.fromkeys(t.get("cimke", "") for t in tetelek))
    uj["cimke"] = cimkek[0] if len(cimkek) == 1 else "Frissítés"
    uj["cimke_en"] = tetelek[0].get("cimke_en", uj["cimke"]) if len(cimkek) == 1 else "Update"
    uj["cimke_de"] = tetelek[0].get("cimke_de", uj["cimke"]) if len(cimkek) == 1 else "Update"
    # a mezők sorrendje a kézzel írt hírekével egyezik
    sorrend = ["datum", "cim", "cimke", "szoveg", "cim_en", "szoveg_en", "cim_de", "szoveg_de", "cimke_en", "cimke_de"]
    return {k: uj[k] for k in sorrend if k in uj}


def main():
    if not os.path.exists(VAROLISTA):
        print("nincs várólista")
        return
    varo, varo_bom = beolvas(VAROLISTA)
    ma = budapesti_ma().isoformat()
    kenyszer = os.environ.get("KENYSZER") == "1"
    esedekes = [t for t in varo if kenyszer or str(t.get("datum", "")) < ma]
    if not esedekes:
        print("nincs esedékes hír (ma: %s, várólistán: %d)" % (ma, len(varo)))
        return
    napok = {}
    for t in esedekes:
        napok.setdefault(str(t["datum"]), []).append(t)
    hirek, hirek_bom = beolvas(HIREK)
    ujak = [osszefuz(d, napok[d]) for d in sorted(napok, reverse=True)]
    kiir(HIREK, ujak + hirek, hirek_bom)
    kiir(VAROLISTA, [t for t in varo if t not in esedekes], varo_bom)
    for u in ujak:
        print("kitéve: %s – %s" % (u["datum"], u["cim"]))


if __name__ == "__main__":
    main()
