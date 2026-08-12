#!/usr/bin/env python3
"""
bancos.py — busca, download e registro de licenca de fotos de banco.

Sem dependencias externas: so stdlib. Roda em qualquer maquina com Python 3.9+.

Bancos suportados:
  pexels     PEXELS_API_KEY      (gratis, cadastro em pexels.com/api)
  unsplash   UNSPLASH_ACCESS_KEY (gratis, cadastro em unsplash.com/developers)
  pixabay    PIXABAY_API_KEY     (gratis, cadastro em pixabay.com/api/docs)
  openverse  sem chave

Adobe Stock nao passa por aqui: use o MCP da Adobe e depois `registrar`.

Uso:
  python bancos.py doctor
  python bancos.py buscar "fiber optic technician" --n 12 --out ./preview/card-03
  python bancos.py baixar pexels:3184418 --como slide-03.jpg --dir assets/imagens/post-1
  python bancos.py registrar --banco adobe --id 714059085 --arquivo <path>
  python bancos.py licencas
"""

import argparse
import concurrent.futures
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

TIMEOUT = 20
UA = "darocha-imagens-para-artes/1.0"
REGISTRO = "LICENCAS.md"


# ----------------------------------------------------------------- utilidades

def _env(nome):
    valor = os.environ.get(nome, "").strip()
    return valor or None


def _carregar_env():
    """Le ~/.claude/imagens.env e ./.env sem sobrescrever o ambiente."""
    for caminho in (Path.home() / ".claude" / "imagens.env", Path(".env")):
        if not caminho.is_file():
            continue
        for linha in caminho.read_text(encoding="utf-8").splitlines():
            linha = linha.strip()
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            chave, _, valor = linha.partition("=")
            chave = chave.strip()
            valor = valor.strip().strip('"').strip("'")
            if chave and chave not in os.environ:
                os.environ[chave] = valor


def _get(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8"))


def _baixar(url, destino: Path, headers=None):
    destino.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r, open(destino, "wb") as f:
        f.write(r.read())
    return destino


def _erro_rede(e):
    texto = str(e)
    if "Forbidden" in texto or "403" in texto or "proxy" in texto.lower():
        return (f"{texto}\n  -> Pode ser allowlist de rede do ambiente. "
                f"Veja references/setup.md.")
    return texto


# -------------------------------------------------------------------- bancos

def buscar_pexels(query, n):
    chave = _env("PEXELS_API_KEY")
    if not chave:
        return []
    url = ("https://api.pexels.com/v1/search?"
           + urllib.parse.urlencode({"query": query, "per_page": n, "orientation": ""}))
    dados = _get(url, {"Authorization": chave})
    saida = []
    for foto in dados.get("photos", []):
        saida.append({
            "banco": "pexels",
            "id": str(foto["id"]),
            "ref": f"pexels:{foto['id']}",
            "autor": foto.get("photographer", ""),
            "licenca": "Pexels License (uso comercial, sem atribuicao obrigatoria)",
            "largura": foto.get("width"),
            "altura": foto.get("height"),
            "thumb": foto["src"]["medium"],
            "full": foto["src"]["original"],
            "pagina": foto.get("url", ""),
        })
    return saida


def buscar_unsplash(query, n):
    chave = _env("UNSPLASH_ACCESS_KEY")
    if not chave:
        return []
    url = ("https://api.unsplash.com/search/photos?"
           + urllib.parse.urlencode({"query": query, "per_page": n}))
    dados = _get(url, {"Authorization": f"Client-ID {chave}"})
    saida = []
    for foto in dados.get("results", []):
        saida.append({
            "banco": "unsplash",
            "id": foto["id"],
            "ref": f"unsplash:{foto['id']}",
            "autor": (foto.get("user") or {}).get("name", ""),
            "licenca": "Unsplash License (uso comercial, atribuicao recomendada)",
            "largura": foto.get("width"),
            "altura": foto.get("height"),
            "thumb": foto["urls"]["small"],
            "full": foto["urls"]["raw"],
            "pagina": (foto.get("links") or {}).get("html", ""),
        })
    return saida


def buscar_pixabay(query, n):
    chave = _env("PIXABAY_API_KEY")
    if not chave:
        return []
    url = ("https://pixabay.com/api/?"
           + urllib.parse.urlencode({
               "key": chave, "q": query, "image_type": "photo",
               "per_page": max(n, 3), "safesearch": "true"}))
    dados = _get(url)
    saida = []
    for foto in dados.get("hits", []):
        saida.append({
            "banco": "pixabay",
            "id": str(foto["id"]),
            "ref": f"pixabay:{foto['id']}",
            "autor": foto.get("user", ""),
            "licenca": "Pixabay Content License (uso comercial)",
            "largura": foto.get("imageWidth"),
            "altura": foto.get("imageHeight"),
            "thumb": foto.get("webformatURL"),
            "full": foto.get("largeImageURL") or foto.get("webformatURL"),
            "pagina": foto.get("pageURL", ""),
        })
    return saida


def buscar_openverse(query, n):
    url = ("https://api.openverse.org/v1/images/?"
           + urllib.parse.urlencode({
               "q": query, "page_size": n,
               "license_type": "commercial", "mature": "false"}))
    dados = _get(url)
    saida = []
    for foto in dados.get("results", []):
        saida.append({
            "banco": "openverse",
            "id": foto["id"],
            "ref": f"openverse:{foto['id']}",
            "autor": foto.get("creator", ""),
            "licenca": f"{(foto.get('license') or '').upper()} "
                       f"{foto.get('license_version', '')}".strip()
                       + " (confira exigencia de atribuicao)",
            "largura": foto.get("width"),
            "altura": foto.get("height"),
            "thumb": foto.get("thumbnail") or foto.get("url"),
            "full": foto.get("url"),
            "pagina": foto.get("foreign_landing_url", ""),
        })
    return saida


PROVEDORES = {
    "pexels": (buscar_pexels, "PEXELS_API_KEY"),
    "unsplash": (buscar_unsplash, "UNSPLASH_ACCESS_KEY"),
    "pixabay": (buscar_pixabay, "PIXABAY_API_KEY"),
    "openverse": (buscar_openverse, None),
}


# ------------------------------------------------------------------ comandos

def cmd_doctor(_args):
    print("Bancos disponiveis nesta maquina:\n")
    for nome, (_, var) in PROVEDORES.items():
        if var is None:
            print(f"  [ok]     {nome:10s} (nao exige chave)")
        elif _env(var):
            print(f"  [ok]     {nome:10s} ({var} configurada)")
        else:
            print(f"  [faltou] {nome:10s} (defina {var} em ~/.claude/imagens.env)")
    print("\n  [MCP]    adobe      use o conector Adobe, nao este script")
    print("\nTeste de rede:")
    try:
        _get("https://api.openverse.org/v1/images/?q=test&page_size=1")
        print("  [ok] saida HTTPS liberada")
    except Exception as e:
        print(f"  [falhou] {_erro_rede(e)}")


def cmd_buscar(args):
    por_banco = max(3, args.n // max(1, len(PROVEDORES)) + 2)
    resultados, erros = [], []

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futuros = {}
        for nome, (fn, var) in PROVEDORES.items():
            if var and not _env(var):
                continue
            futuros[pool.submit(fn, args.query, por_banco)] = nome
        for fut in concurrent.futures.as_completed(futuros):
            nome = futuros[fut]
            try:
                resultados.extend(fut.result())
            except Exception as e:
                erros.append(f"{nome}: {_erro_rede(e)}")

    # ordena pelas maiores, que dao mais margem de crop
    resultados.sort(key=lambda r: (r.get("largura") or 0) * (r.get("altura") or 0),
                    reverse=True)
    resultados = resultados[:args.n]

    destino = Path(args.out)
    destino.mkdir(parents=True, exist_ok=True)

    for i, r in enumerate(resultados, 1):
        nome_arq = f"{i:02d}-{r['banco']}-{r['id']}.jpg"
        try:
            _baixar(r["thumb"], destino / nome_arq)
            r["arquivo_preview"] = str(destino / nome_arq)
        except Exception as e:
            r["arquivo_preview"] = None
            erros.append(f"thumb {r['ref']}: {_erro_rede(e)}")

    (destino / "resultados.json").write_text(
        json.dumps({"query": args.query, "resultados": resultados, "erros": erros},
                   ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"{len(resultados)} resultado(s) para \"{args.query}\" em {destino}\n")
    for i, r in enumerate(resultados, 1):
        dim = f"{r.get('largura')}x{r.get('altura')}"
        print(f"  {i:02d}. {r['ref']:28s} {dim:12s} {r['autor']}")
    if erros:
        print("\nAvisos:")
        for e in erros:
            print(f"  - {e}")
    print(f"\nAgora olhe as miniaturas em {destino} antes de baixar qualquer coisa.")


def cmd_baixar(args):
    banco, _, ident = args.ref.partition(":")
    if banco not in PROVEDORES:
        sys.exit(f"Banco desconhecido: {banco}. Para Adobe Stock use o MCP.")

    origem = None
    for cand in Path(".").rglob("resultados.json"):
        dados = json.loads(cand.read_text(encoding="utf-8"))
        for r in dados.get("resultados", []):
            if r["ref"] == args.ref:
                origem = r
                break
        if origem:
            break
    if not origem:
        sys.exit(f"Nao achei {args.ref} em nenhum resultados.json. "
                 f"Rode `buscar` antes, na mesma pasta do projeto.")

    destino = Path(args.dir) / args.como
    headers = {}
    if banco == "unsplash":
        headers["Authorization"] = f"Client-ID {_env('UNSPLASH_ACCESS_KEY')}"
    try:
        _baixar(origem["full"], destino, headers)
    except Exception as e:
        sys.exit(f"Falha no download: {_erro_rede(e)}")

    kb = destino.stat().st_size // 1024
    _registrar(banco=banco, ident=ident, autor=origem.get("autor", ""),
               licenca=origem.get("licenca", ""), pagina=origem.get("pagina", ""),
               arquivo=str(destino), card=args.card or "")
    print(f"Salvo em {destino} ({kb} KB) e registrado em {REGISTRO}")


def cmd_registrar(args):
    _registrar(banco=args.banco, ident=args.id, autor=args.autor or "",
               licenca=args.licenca or "licenca padrao do banco",
               pagina=args.pagina or "", arquivo=args.arquivo, card=args.card or "")
    print(f"Registrado em {REGISTRO}")


def _registrar(banco, ident, autor, licenca, pagina, arquivo, card):
    reg = Path(REGISTRO)
    if not reg.exists():
        reg.write_text(
            "# Registro de licencas de imagem\n\n"
            "Gerado por `bancos.py`. Nao editar as linhas a mao sem manter o formato.\n\n"
            "| Data | Banco | ID | Card | Arquivo | Autor | Licenca | Origem |\n"
            "|---|---|---|---|---|---|---|---|\n", encoding="utf-8")
    linha = (f"| {date.today().isoformat()} | {banco} | {ident} | {card} | "
             f"{arquivo} | {autor} | {licenca} | {pagina} |\n")
    with open(reg, "a", encoding="utf-8") as f:
        f.write(linha)


def cmd_licencas(_args):
    encontrados = sorted(Path(".").rglob(REGISTRO))
    if not encontrados:
        print("Nenhum LICENCAS.md encontrado a partir desta pasta.")
        return
    for reg in encontrados:
        print(f"\n=== {reg} ===")
        print(reg.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------- main

def main():
    _carregar_env()
    p = argparse.ArgumentParser(description="Busca e licenciamento de fotos de banco.")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("doctor", help="verifica chaves e rede").set_defaults(fn=cmd_doctor)

    b = sub.add_parser("buscar", help="busca em todos os bancos e baixa miniaturas")
    b.add_argument("query", help="termo em ingles, 2 a 4 palavras")
    b.add_argument("--n", type=int, default=12, help="quantos resultados no total")
    b.add_argument("--out", default="./preview", help="pasta das miniaturas")
    b.set_defaults(fn=cmd_buscar)

    d = sub.add_parser("baixar", help="baixa em alta e registra a licenca")
    d.add_argument("ref", help="ex: pexels:3184418")
    d.add_argument("--como", required=True, help="ex: slide-03.jpg")
    d.add_argument("--dir", required=True, help="ex: assets/imagens/post-1")
    d.add_argument("--card", help="descricao do card, vai para o registro")
    d.set_defaults(fn=cmd_baixar)

    r = sub.add_parser("registrar", help="registra manualmente (uso: Adobe Stock)")
    r.add_argument("--banco", required=True)
    r.add_argument("--id", required=True)
    r.add_argument("--arquivo", required=True)
    r.add_argument("--autor")
    r.add_argument("--licenca")
    r.add_argument("--pagina")
    r.add_argument("--card")
    r.set_defaults(fn=cmd_registrar)

    sub.add_parser("licencas", help="mostra os registros existentes").set_defaults(fn=cmd_licencas)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
