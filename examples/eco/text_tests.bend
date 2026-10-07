import Base
import ./text.bend as T
import ../../scene.bend as S
import ../../../Runika/font.bend as F

# Native checks of the demo's text cache (text.bend): cached runs equal
# runs prepared from scratch, bit for bit; a text prepared again is a hit
# (no new run, no new glyph); a new width is a miss; a font with another
# checksum starts an empty cache; generations keep the cache bounded while
# a text in use stays cached; and runs that share a hash never mix up.
# Run from the Chromi directory: ./build/text_tests --threads 2 --gpu off

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ message)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ message)

def same_words(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{a, ra} Con{b, rb}:
      U32.is_eq(a, b) && same_words(ra, rb)
    case _ _:
      False{}

def same_bool(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

def same_pixels(a: S.Pixels, b: S.Pixels) -> Bool:
  match a b:
    case S.Pixels{ka, wa, ha, da, ma} S.Pixels{kb, wb, hb, db, mb}:
      U32.is_eq(ka, kb) && U32.is_eq(wa, wb) && U32.is_eq(ha, hb) && same_words(da, db) && same_bool(ma, mb)

def same_placed(xs: List<&2, T.Placed>, ys: List<&2, T.Placed>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{T.Placed{ax, ay, ap}, ra} Con{T.Placed{bx, by, bp}, rb}:
      F32.is_eq(ax, bx) && F32.is_eq(ay, by) && same_pixels(ap, bp) && same_placed(ra, rb)
    case _ _:
      False{}

def same_run(a: T.Run, b: T.Run) -> Bool:
  match a b:
    case T.Run{sa, wa, ha, aa, ga} T.Run{sb, wb, hb, ab, gb}:
      F32.is_eq(sa, sb) && F32.is_eq(wa, wb) && F32.is_eq(ha, hb) && F32.is_eq(aa, ab) && same_placed(ga, gb)

def run_or(r: Result<&2, &2, String, T.Run>) -> Maybe<&2, T.Run>:
  match r:
    case Fail{e}:
      None{}
    case Done{run}:
      Some{run}

def prepared_run(r: Result<&2, &2, String, T.Prepared>) -> Maybe<&2, T.Run>:
  match r:
    case Fail{e}:
      None{}
    case Done{T.Prepared{run, c}}:
      Some{run}

def prepared_cache(r: Result<&2, &2, String, T.Prepared>) -> T.Cache:
  match r:
    case Fail{e}:
      T.cache()
    case Done{T.Prepared{run, c}}:
      c

def same_maybe(a: Maybe<&2, T.Run>, b: Maybe<&2, T.Run>) -> Bool:
  match a b:
    case Some{x} Some{y}:
      same_run(x, y)
    case _ _:
      False{}

# The demo's seven texts at the demo's sizes and widths (column 492).
type Text is Data:
  Text{text: String, size: F32, width: F32}

def texts(+n: U32) -> List<&2, Text>:
  [Text{"AMAGE Eco", 34.0, 492.0}, Text{"Uma janela, uma GPU, várias bibliotecas.", 19.0, 492.0},
    Text{"Texto real em Bend: ação, coração, café. A Ankra cuida da janela e dos eventos, a Voltra da GPU e o Chromi da lista de desenho.", 16.0, 492.0},
    Text{"Ativar", 18.0, 1000000.0}, Text{"Ativado " ++ U32.show(n) ++ " vezes.", 16.0, 492.0},
    Text{"PNG decodificado pela Ocula", 13.0, 1000000.0}, Text{"SVG interpretado pela Splina", 13.0, 1000000.0}]

type Pass is Data:
  Pass{cache: T.Cache, same: Bool}

# Prepares each text through the cache and compares it with the run
# prepared from scratch.
def pass(ts: List<&2, Text>, +font: F.Font, p: Pass) -> Pass:
  match ts:
    case Nil{}:
      p
    case Con{Text{+t, +s, +w}, rest}:
      Pass{c, ok} = p
      +r = T.prepare(font, t, s, w, c)
      pass(rest, font, Pass{prepared_cache(r), ok && same_maybe(prepared_run(r), run_or(T.prepare_uncached(font, t, s, w)))})

def pass_cache(p: Pass) -> T.Cache:
  Pass{c, ok} = p
  c

def pass_same(p: Pass) -> Bool:
  Pass{c, ok} = p
  ok

# The font with another checksum (same tables).
def renamed(f: F.Font) -> F.Font:
  match f:
    case F.Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      F.Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, (sum + 1 : U32), latin}
    case F.Alias{inner}:
      renamed(inner)

# Prepares "n0", "n1", ... (n texts), and "keep" before each tenth.
def churn(n: Nat, +i: U32, +font: F.Font, +c: T.Cache) -> T.Cache:
  match n:
    case 0n:
      c
    case 1n+p:
      +c1 = Bool.pick(T.Cache, U32.is_eq((i % 10 : U32), 0), prepared_cache(T.prepare(font, "keep", 16.0, 1000000.0, c)), c)
      churn(p, (i + 1 : U32), font, prepared_cache(T.prepare(font, "n" ++ U32.show(i), 16.0, 1000000.0, c1)))

def counts(+c: T.Cache) -> String:
  U32.show(T.run_count(c)) ++ " runs, " ++ U32.show(T.glyph_count(c)) ++ " glyphs"

def need(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{message}:
      IO.die(A, 1, message)
    case Done{x}:
      IO.pure(A, x)

def body() -> String:
  "Texto real em Bend: ação, coração, café. A Ankra cuida da janela e dos eventos, a Voltra da GPU e o Chromi da lista de desenho."

# Whether the cache holds a run for this text, size and width (either
# generation).
def cached(+c: T.Cache, +text: String, +size: F32, +width: F32) -> Bool:
  +h = T.hash(text, size, width)
  Maybe.is_some(&2, T.Run, T.find(T.fresh_of(c), h, text, size, width)) ||
    Maybe.is_some(&2, T.Run, T.find(T.stale_of(c), h, text, size, width))

def run_default(m: Maybe<&2, T.Run>) -> T.Run:
  Maybe.default(&2, T.Run, m, T.Run{0.0, 0.0, 0.0, 0.0, Nil{}})

def main() -> IO(Unit):
  do IO<Unit>:
    loaded : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- need(F.Font, loaded)
    +first : Pass = pass(texts(1), font, Pass{T.cache(), True{}})
    +c1 : T.Cache = pass_cache(first)
    check(pass_same(first), "cached runs equal runs prepared from scratch, bit for bit (7 demo texts: " ++ counts(c1) ++ ")")
    +again : Pass = pass(texts(1), font, Pass{c1, True{}})
    +c2 : T.Cache = pass_cache(again)
    check(pass_same(again) && U32.is_eq(T.run_count(c2), T.run_count(c1)) && U32.is_eq(T.glyph_count(c2), T.glyph_count(c1)),
      "the same texts again are hits: no new run, no new glyph")
    +next : Pass = pass(texts(2), font, Pass{c2, True{}})
    +c3 : T.Cache = pass_cache(next)
    check(pass_same(next) && U32.is_eq(T.run_count(c3), (T.run_count(c2) + 1 : U32)),
      "a changed text (the status) is one new run, equal to the uncached one")
    +wide : Result<&2, &2, String, T.Prepared> = T.prepare(font, body(), 16.0, 300.0, c3)
    check(same_maybe(prepared_run(wide), run_or(T.prepare_uncached(font, body(), 16.0, 300.0))) &&
      U32.is_eq(T.run_count(prepared_cache(wide)), (T.run_count(c3) + 1 : U32)) && cached(c3, body(), 16.0, 492.0) &&
      Bool.not(cached(c3, body(), 16.0, 300.0)), "a new width is a miss, laid out again")
    +other : F.Font = renamed(font)
    +moved : Result<&2, &2, String, T.Prepared> = T.prepare(other, "AMAGE Eco", 34.0, 492.0, c3)
    +alone : Result<&2, &2, String, T.Prepared> = T.prepare(other, "AMAGE Eco", 34.0, 492.0, T.cache())
    check(U32.is_eq(T.run_count(prepared_cache(moved)), 1) &&
      U32.is_eq(T.glyph_count(prepared_cache(moved)), T.glyph_count(prepared_cache(alone))) &&
      same_maybe(prepared_run(moved), run_or(T.prepare_uncached(other, "AMAGE Eco", 34.0, 492.0))),
      "a font with another checksum starts an empty cache")
    +churned : T.Cache = churn(600n, 0, font, T.cache())
    check(U32.is_le(T.run_count(churned), 512) && cached(churned, "keep", 16.0, 1000000.0) &&
      cached(churned, "n599", 16.0, 1000000.0) && Bool.not(cached(churned, "n0", 16.0, 1000000.0)),
      "600 changing texts stay within two generations (" ++ counts(churned) ++ "); a text in use stays cached")
    +ra : T.Run = run_default(run_or(T.prepare_uncached(font, "a", 16.0, 100.0)))
    +rb : T.Run = run_default(run_or(T.prepare_uncached(font, "b", 16.0, 100.0)))
    +shared : T.Cache = T.remember(T.remember(T.cache(), 7, T.Entry{"a", 16.0, 100.0, ra}), 7, T.Entry{"b", 16.0, 100.0, rb})
    check(same_maybe(T.find(T.fresh_of(shared), 7, "a", 16.0, 100.0), Some{ra}) &&
      same_maybe(T.find(T.fresh_of(shared), 7, "b", 16.0, 100.0), Some{rb}) &&
      Maybe.is_none(&2, T.Run, T.find(T.fresh_of(shared), 7, "c", 16.0, 100.0)) &&
      Maybe.is_none(&2, T.Run, T.find(T.fresh_of(shared), 7, "a", 16.0, 101.0)),
      "runs that share a hash are told apart by text, size and width")
    IO.print("7 text cache checks passed")
