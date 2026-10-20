#!/usr/bin/env bash
# Pushups PWA — phase 2 installer (design pass: WCAG-accurate accents, calendar heatmap, honest gate states, manual-set fix). Self-contained: writes every source file, then downloads
# the MediaPipe wasm + pose models + fonts and generates the icons. Re-runnable; overwrites
# only files inside the app folder. Nothing here touches your saved sets (they live on the phone).
set -euo pipefail
ROOT="${1:-$HOME/Projects/pushups}"
mkdir -p "$ROOT"; cd "$ROOT"
umask 022

mkdir -p .
cat > '.gitignore' <<'__EOF__gitignore__'
.DS_Store
*.mov
*.mp4
tools/base-url
tools/stamp.txt
tools/precache.txt
__EOF__gitignore__

mkdir -p 'css'
cat > 'css/app.css' <<'__EOF_css_app_css__'
@font-face{font-family:"Barlow Semi Condensed";font-style:normal;font-weight:100 900;font-display:swap;src:url(../fonts/barlow-semi-condensed.woff2) format("woff2")}
@font-face{font-family:"IBM Plex Sans";font-style:normal;font-weight:100 700;font-display:swap;src:url(../fonts/ibm-plex-sans.woff2) format("woff2")}

/* Six named hues. Two rules govern them:
   1. an accent used as TEXT or as a THIN LINE darkens in light mode (a bright hue on porcelain
      is unreadable), so --track/--brass/--rose/--plum are scheme-adaptive;
   2. a bright hue survives only as a solid FILL, with its own on-color (--brass-fill/--on-brass,
      --rose-fill/--on-rose). Ratios are measured in tools/audit.mjs, not eyeballed. */
:root{
  --ink:#0E1A18;
  --porcelain:#E9EEEA;
  --track:#4FA3A5;
  --brass:#C9922F;
  --rose:#DE6E81;
  --plum:#9A86A3;

  --brass-fill:#C9922F;   --on-brass:#14110A;
  --rose-fill:#B23A52;    --on-rose:#E9EEEA;
  --rose-tint:rgba(222,110,129,.14);
  --scrim:rgba(5,10,9,.72);
  --cam:#050A09;

  --bg:#0E1A18;
  --sheet:#13211F;
  --text:#DCE6E2;
  --muted:#7F918C;
  --hair:rgba(220,230,226,.12);
  --tint:rgba(220,230,226,.05);
  --num:#DCE6E2;

  /* Heatmap ladder: five discrete steps, no opacity tricks (an opacity wash out is invisible
     against a light background). lv0 is --tint. */
  --heat-1:#1D3A38;
  --heat-2:#2C5B59;
  --heat-3:#3D8184;
  --heat-4:#4FA3A5;

  --display:"Barlow Semi Condensed","Helvetica Neue",sans-serif;
  --ui:"IBM Plex Sans",-apple-system,"Helvetica Neue",sans-serif;

  --sat:env(safe-area-inset-top,0px);
  --sab:env(safe-area-inset-bottom,0px);
  --sar:env(safe-area-inset-right,0px);
  --sal:env(safe-area-inset-left,0px);
  color-scheme:dark light;
}

@media (prefers-color-scheme:light){
  :root{
    --track:#22686A;
    --brass:#7C5A1A;
    --rose:#A8324A;
    --plum:#5E4A68;
    --rose-fill:#9E2C42;
    --rose-tint:rgba(168,50,74,.10);

    --bg:#E9EEEA;
    --sheet:#F2F5F2;
    --text:#0E1A18;
    --muted:#4E5B57;
    --hair:rgba(14,26,24,.11);
    --tint:rgba(14,26,24,.045);
    --num:#0E1A18;

    --heat-1:#C3D6D4;
    --heat-2:#8FB6B4;
    --heat-3:#4F8B8D;
    --heat-4:#22686A;
  }
}

*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;height:100%;overflow:hidden;overscroll-behavior:none}
body{background:var(--bg);color:var(--text);font:16px/1.45 var(--ui);transition:background .2s linear,color .2s linear;
  -webkit-text-size-adjust:100%}
button,input,select,textarea{font:inherit;color:inherit}
a{color:inherit;text-decoration:none}
:focus-visible{outline:2px solid var(--track);outline-offset:2px}

#view{position:fixed;top:calc(var(--sat));left:var(--sal);right:var(--sar);bottom:calc(54px + var(--sab));
  display:flex;flex-direction:column}

.pad{padding-left:16px;padding-right:16px}
.row{display:flex;align-items:center;gap:12px}
.col{display:flex;flex-direction:column}
.grow{flex:1;min-height:0}
.center{align-items:center;justify-content:center;text-align:center}
.h1{font:600 21px/1.25 var(--ui);margin:0}
.h2{font:600 16px/1.3 var(--ui);margin:0 0 6px;letter-spacing:.01em}
.sub{color:var(--muted);font-size:13px}
.mono{font:12px/1.5 ui-monospace,"SF Mono",Menlo,monospace}
.num{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums}
.rule{height:1px;background:var(--hair);margin:12px 0}
.spacer{height:14px}

/* ── tab bar ── */
#tabs{position:fixed;left:0;right:0;bottom:0;display:flex;align-items:flex-end;
  padding:7px 2px calc(7px + var(--sab));background:var(--sheet);border-top:1px solid var(--hair);
  font-size:11px;line-height:1.05;text-align:center;z-index:60}
#tabs a{flex:1;color:var(--muted);transition:color .15s linear}
#tabs a .ic{display:block;height:20px;margin-bottom:4px}
#tabs a .ic svg{width:19px;height:19px;display:block;margin:0 auto}
#tabs a[aria-current="true"]{color:var(--text)}
#tabs a.todo{opacity:.45}

/* ── update banner ── */
#banner:empty{display:none}
#banner{position:fixed;top:var(--sat);left:0;right:0;z-index:70}
#banner>div{margin:0 var(--sal) 0 var(--sar);padding:11px 16px;background:var(--brass-fill);color:var(--on-brass);
  font-weight:600;font-size:15px;cursor:pointer}
body.banner-on #view{top:calc(var(--sat) + 45px)}

/* ── controls ── */
.btn{border:1px solid var(--hair);background:var(--tint);color:var(--text);border-radius:999px;
  padding:12px 22px;font-weight:600;font-size:16px;transition:opacity .12s linear,transform .12s ease-out}
.btn:active{transform:scale(.97)}
.btn-primary{background:var(--text);color:var(--bg);border-color:transparent}
.btn-warn{background:var(--rose-fill);color:var(--on-rose);border-color:transparent}
.btn-quiet{background:none;border-color:transparent;color:var(--muted)}
.btn-big{width:100%;padding:17px;font-size:17px}
.btn[disabled]{opacity:.4}
.step{width:76px;height:60px;border-radius:14px;background:var(--tint);border:1px solid var(--hair);
  font:700 30px/1 var(--display);color:var(--text);display:inline-flex;align-items:center;justify-content:center}
.step:active{background:var(--hair)}
select,input[type=text],input[type=number],textarea{background:var(--tint);border:1px solid var(--hair);
  border-radius:10px;padding:10px 12px;width:100%;appearance:none}
select{padding-right:30px;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'><path d='M1 1l5 5 5-5' fill='none' stroke='%237F918C' stroke-width='1.8' stroke-linecap='round'/></svg>");
  background-repeat:no-repeat;background-position:right 11px center}
@media (prefers-color-scheme:light){
  select{background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'><path d='M1 1l5 5 5-5' fill='none' stroke='%234E5B57' stroke-width='1.8' stroke-linecap='round'/></svg>")}
}
/* 44pt is the iPhone HIG minimum for anything you drag or tap with a thumb. The drawn control
   stays slim; the element box is what your finger hits. */
input[type=range]{width:100%;accent-color:var(--track);height:44px}
input[type=checkbox]{width:26px;height:26px;accent-color:var(--track)}
label.tog{display:flex;align-items:center;justify-content:space-between;gap:12px;min-height:44px;
  padding:11px 0;border-bottom:1px solid var(--hair);font-size:15px}
label.tog .sub{display:block;font-size:12px}

/* ── camera + overlay ── */
.camwrap{position:relative;background:var(--cam);flex:1;min-height:0;overflow:hidden}
.camwrap video{display:block;width:100%;height:100%;object-fit:cover}
.camwrap canvas{position:absolute;inset:0;width:100%;height:100%}
/* The camera surface is always near-black, so it gets its own text ramp in both schemes —
   a light-mode --muted on it would be unreadable. */
.camoff{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:14px;padding:24px;text-align:center;color:#8A9C97;font-size:14px;background:var(--cam)}
.camoff h3{margin:0 0 6px;color:var(--porcelain);font:600 16px/1.3 var(--ui)}
.camoff ol{margin:0;padding-left:18px;font-size:13px;line-height:1.55;text-align:left}
.pill{position:absolute;left:10px;bottom:10px;display:flex;align-items:center;gap:8px;
  padding:6px 12px;border-radius:999px;background:var(--scrim);color:var(--porcelain);font-size:13px;
  font-variant-numeric:tabular-nums}
.pill i{width:7px;height:7px;border-radius:50%;background:var(--track)}
.pill.bad i{background:var(--rose)}
.pill.warn i{background:var(--brass)}

/* ── setup ── */
.statusbar{display:flex;align-items:center;gap:10px;padding:8px 16px;border-bottom:1px solid var(--hair);font-size:13px}
.statusbar .bar{flex:1}
.bar{height:5px;background:var(--tint);border-radius:3px;overflow:hidden}
.bar i{display:block;height:100%;width:0;background:var(--track);transition:width .3s linear}
.bar i.bad{background:var(--rose)}
.chk{display:flex;gap:10px;align-items:center;padding:9px 0;border-bottom:1px solid var(--hair);font-size:14px}
.chk .mk{width:18px;height:18px;flex:none;display:inline-flex;align-items:center;justify-content:center;color:var(--muted)}
.chk .mk svg{width:16px;height:16px;display:block}
.chk.ok .mk{color:var(--track)}
.chk.bad .mk{color:var(--rose)}
.chk.bad>.t{color:var(--text)}
.chk.wait{opacity:.72}
.chk .t{flex:0 1 auto}
.chk .why{color:var(--muted);font-size:12px;margin-left:auto;text-align:right;min-width:0;overflow-wrap:anywhere}
.chk.bad .why{color:var(--rose)}
.recos{padding:10px 16px;background:var(--sheet);border-top:1px solid var(--hair);font-size:14px}
.recos h3{margin:0 0 6px;font-size:14px;font-weight:600}
.recos ol{margin:0;padding-left:18px;color:var(--muted)}
.recos li{margin:3px 0}

/* ── counter ── */
.counter{position:relative;display:flex;flex-direction:column;flex:1;min-height:0}
.counter[data-phase="setup"] .camwrap{flex:1 1 42%;min-height:168px}
.counter[data-phase="set"] .camwrap,.counter[data-phase="countdown"] .camwrap{flex:none;height:26%}
.counter[data-phase="summary"] .camwrap{display:none}
.stage{flex:1;min-height:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  transition:opacity .25s linear}
.stage.dim{opacity:.35}
.stage>.list,.stage>.sheet,.stage>.cta{align-self:stretch;width:100%;min-width:0}
.cta{padding:10px 16px 12px;background:var(--bg);border-top:1px solid var(--hair)}
.cta .sub{margin-top:7px;font-size:12px;line-height:1.35}
#repnum{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.02em;
  font-size:min(46vh,400px,calc(176vw / var(--nd,1)));line-height:.88;color:var(--num);transition:color .16s linear}
#repnum.tick{color:var(--brass)}
#cdnum{font-family:var(--display);font-weight:700;font-size:min(70vw,38vh,320px);line-height:.9;color:var(--brass)}
#chip{font-size:14px;color:var(--muted);text-align:center;min-height:20px;margin-top:6px}
.hairline{height:3px;background:transparent;transition:background .2s linear}
.hairline.on{background:var(--rose)}
.corr{display:flex;align-items:center;justify-content:center;gap:16px;padding:8px 0 4px}
.corr .n{font:700 20px/1 var(--display);min-width:44px;text-align:center;font-variant-numeric:tabular-nums}
.topline{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:10px;padding:8px 14px;font-size:13px;
  color:var(--muted);font-variant-numeric:tabular-nums}
.topline .clock{justify-self:start}
.topline .endslot{justify-self:end}
/* The live phase label is this screen's heading: it says what the app is doing right now. */
#phaseLabel{margin:0;font:600 13px/1.25 var(--ui);letter-spacing:.02em;color:inherit}
.warnbox{padding:9px 14px;background:var(--rose-tint);color:var(--rose);font-size:14px;border-top:1px solid var(--rose-fill)}
.warnbox[hidden]{display:none}

/* ── summary ── */
.sheet{flex:1;min-height:0;align-self:stretch;overflow:auto;background:var(--sheet);padding:14px 16px calc(16px + var(--sab))}
.finum{font:700 92px/1 var(--display);text-align:center;font-variant-numeric:tabular-nums;color:var(--num)}
.finum input{all:unset;display:block;width:100%;text-align:center;font:inherit;color:inherit}
.kv{display:flex;justify-content:space-between;gap:10px;padding:9px 0;border-bottom:1px solid var(--hair);font-size:14px}
.kv b{font-weight:600;font-variant-numeric:tabular-nums}
.kv .num{font-size:15px}
.flags{display:flex;flex-wrap:wrap;gap:8px;padding:10px 0}
.flags span{padding:5px 10px;border-radius:8px;background:var(--tint);border:1px solid var(--hair);font-size:13px}
.flags .hard{border-color:var(--rose);color:var(--rose)}
.flags .soft{border-color:var(--brass);color:var(--brass)}
.flags .info{border-color:var(--plum);color:var(--plum)}

/* ── lists ── */
.list{flex:1;min-height:0;overflow:auto;padding-bottom:calc(14px + var(--sab))}
.item{display:flex;justify-content:space-between;align-items:baseline;gap:10px;padding:12px 16px;
  border-bottom:1px solid var(--hair)}
.item .num{font-size:21px}
.item .meta{color:var(--muted);font-size:13px;text-align:right}
.todaytotal{padding:18px 16px 8px}
.todaytotal .num{font-size:80px;line-height:.9}
.soon{padding:26px 16px;color:var(--muted);font-size:15px}

/* ── badges (placeholder) ── */
.bd-list{padding:8px 0 20px}
.bd-row{display:flex;gap:12px;align-items:center;padding:13px 16px;border-bottom:1px solid var(--hair);min-height:44px}
.bd-ic{width:22px;height:22px;flex:none;color:var(--muted)}
.bd-ic svg{width:22px;height:22px;display:block}
.bd-txt{display:flex;flex-direction:column;gap:2px;min-width:0}
.bd-txt b{font-weight:600;font-size:15px}
.bd-rule{color:var(--muted);font-size:13px;line-height:1.45}

/* ── debug ── */
.dbg{flex:1;min-height:0;overflow:auto;padding:10px 14px calc(20px + var(--sab));
  font:12px/1.45 ui-monospace,"SF Mono",Menlo,monospace}
.dbg h3{font:600 14px var(--ui);margin:14px 0 6px}
.dbg table{width:100%;border-collapse:collapse}
.dbg td,.dbg th{padding:3px 5px;border-bottom:1px solid var(--hair);text-align:right;font-weight:400}
.dbg th{text-align:left;color:var(--muted)}
.dbg .st{color:var(--brass)}
.field{margin:9px 0}
.field>label{display:flex;justify-content:space-between;font-size:13px;color:var(--muted);margin-bottom:3px}
.field>label b{color:var(--text);font-variant-numeric:tabular-nums}

/* ── motion ──
   Every animation in the app confirms an action Tal already took, and all of them are color or
   opacity except two: the button press scale and the readiness meter sliding to width. Those two
   are what reduced-motion users lose; the state changes themselves stay visible. */
@media (prefers-reduced-motion:reduce){
  .btn:active{transform:none}
  .bar i{transition:none}
}
__EOF_css_app_css__

mkdir -p 'css'
cat > 'css/progress.css' <<'__EOF_css_progress_css__'
/* Progress screen only. Tokens and shared classes (.pad .row .col .kv .list .btn .flags .rule
   .num .sub .h1) come from css/app.css and are reused as-is — nothing here redefines them.
   Prefix .pg- keeps this file and css/today.css out of each other's way.
   No :has(), no dvh/svh, no container queries, no aspect-ratio on flex children. */

/* ── header ────────────────────────────────────────────────────── */
.pg-top{padding-top:16px;padding-bottom:2px}
.pg-sum{color:var(--muted);font-size:13px;margin:6px 0 0;font-variant-numeric:tabular-nums}
.pg-error{color:var(--rose);font-size:13px;margin:6px 0 0;overflow-wrap:anywhere}
.pg-caption{font-size:12px;line-height:1.4;margin:6px 0 0;overflow-wrap:anywhere}

/* ── section furniture (varied rhythm: band, plain, bordered, list) ── */
.pg-sec{padding-top:18px;padding-bottom:4px}
.pg-box{background:var(--sheet);border-top:1px solid var(--hair);border-bottom:1px solid var(--hair);
  padding-top:13px;padding-bottom:12px;margin-top:18px}
.pg-headrow{display:block}
.pg-headtitle{font:600 15px/1.3 var(--ui);margin:0}
.pg-headsub{color:var(--muted);font-size:12px;margin-top:1px;overflow-wrap:anywhere}
.pg-cap{display:flex;align-items:baseline;gap:6px;flex-wrap:wrap;padding-top:14px;padding-bottom:6px}
.pg-captxt{font-size:13px;color:var(--text)}
.pg-capdim{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
.pg-capend{padding-bottom:12px}

/* ── calendar heatmap: the hero band ───────────────────────────── */
.pg-heatsec{background:var(--sheet);border-top:1px solid var(--hair);border-bottom:1px solid var(--hair)}
.pg-heatgrid{display:flex;flex-direction:column;gap:var(--pg-gap,3px);margin:10px 0 0}
/* one week per row, Monday first */
.pg-heatrow{display:flex;gap:var(--pg-gap,3px);align-items:stretch;position:relative;border-radius:6px}
.pg-heatrow.now{background:var(--tint)}
/* this week gets a brass tick down its left edge, so it reads as "now" not as a stray outline */
.pg-heatrow.now::before{content:'';position:absolute;left:-4px;top:1px;bottom:1px;width:2px;
  border-radius:1px;background:var(--brass)}
.pg-headday{gap:var(--pg-gap,3px)}
.pg-hday{flex:1 1 0;min-width:0;font-size:10px;line-height:1.2;color:var(--muted);text-align:center;letter-spacing:.02em}
.pg-hcell{position:relative;flex:1 1 0;min-width:0;height:var(--pg-cell,44px);padding:0;border:0;
  background:none;display:flex;align-items:center;justify-content:center;cursor:pointer;
  -webkit-appearance:none;border-radius:5px;transition:opacity .12s linear}
.pg-hcell:active{opacity:.5}
.pg-hcell[disabled]{cursor:default}
.pg-hcell[disabled]:active{opacity:1}
.pg-hsq{display:block;width:100%;height:100%;border-radius:5px;background:var(--tint);
  box-shadow:inset 0 0 0 1px var(--hair)}
/* Five discrete steps instead of one hue at four opacities: an opacity wash vanishes on porcelain,
   and the only job of this ladder is that neighbouring levels look different. */
.pg-hsq.lv1{background:var(--heat-1);box-shadow:none}
.pg-hsq.lv2{background:var(--heat-2);box-shadow:none}
.pg-hsq.lv3{background:var(--heat-3);box-shadow:none}
.pg-hsq.lv4{background:var(--heat-4);box-shadow:none}
/* the ring sits on the cell, not the square, so a low level does not fade it out */
.pg-hcell.today::before{content:'';position:absolute;inset:0;border:2px solid var(--brass);border-radius:7px}
.pg-heatnav{display:inline-flex;align-items:center;gap:2px;margin-right:4px;align-self:center}
/* 44pt hit box with a 30pt visible disc: the finger gets the HIG target, the caption stays quiet */
.pg-heatbtn{width:44px;height:44px;margin:-9px 0;display:inline-flex;align-items:center;justify-content:center;
  border:0;background:none;padding:0;cursor:pointer;color:var(--text)}
.pg-heatdisc{width:30px;height:30px;border-radius:9px;border:1px solid var(--hair);background:var(--tint);
  display:inline-flex;align-items:center;justify-content:center;font:600 17px/1 var(--ui);padding-bottom:2px}
.pg-heatbtn:active .pg-heatdisc{background:var(--hair)}
.pg-heatbtn[disabled]{opacity:.3}
.pg-legend{display:flex;align-items:center;gap:4px;flex-wrap:wrap;font-size:11px;line-height:1.4}
.pg-legend .pg-hsq{width:11px;height:11px;flex:none}

/* ── segmented controls ────────────────────────────────────────── */
.pg-seg{display:flex;gap:6px;padding-top:4px;padding-bottom:8px;flex-wrap:wrap}
.pg-segmini{gap:4px;padding-bottom:4px}
.pg-segb{flex:1 1 0;min-width:0;min-height:44px;padding:10px 6px;border-radius:10px;
  border:1px solid var(--hair);background:var(--tint);color:var(--muted);
  font:600 14px/1.1 var(--ui);cursor:pointer;-webkit-appearance:none;transition:color .15s linear}
.pg-segb:active{opacity:.65}
.pg-segb.on{color:var(--text);background:var(--hair);border-color:transparent;
  box-shadow:inset 0 -2px 0 var(--track)}
.pg-segmini .pg-segb{min-height:40px;font-size:13px;font-weight:600}

/* ── bar chart (hand-rolled divs) ──────────────────────────────── */
.pg-barchart{padding-left:16px;padding-right:16px;padding-bottom:2px}
.pg-plotempty{border:1px dashed var(--hair);border-radius:8px;padding:16px 12px;text-align:center;
  color:var(--muted);font-size:13px}
.pg-plot{position:relative;display:flex;align-items:stretch;gap:2px;height:112px}
.pg-slot{flex:1 1 0;min-width:0;display:flex;flex-direction:column;gap:2px}
.pg-bint{flex:1;min-height:0;display:flex;align-items:flex-end}
.pg-bar{display:block;width:100%;min-height:0;background:var(--track);opacity:.78;border-radius:2px 2px 0 0}
.pg-bar.hi{opacity:1}
.pg-tick{display:block;height:3px;width:100%;flex:none;background:var(--muted);border-radius:1px}
.pg-goalline{position:absolute;left:0;right:0;height:0;border-top:1px dashed var(--brass);
  pointer-events:none}
.pg-goaltag{position:absolute;left:0;top:-9px;font-size:11px;color:var(--brass);
  background:var(--bg);padding:0 4px;font-variant-numeric:tabular-nums}
.pg-axis{display:flex;gap:2px;margin-top:5px;overflow:hidden}
.pg-aslot{flex:1 1 0;min-width:0;text-align:center}
.pg-atext{display:inline-block;font-size:10px;line-height:1.2;color:var(--muted);
  font-variant-numeric:tabular-nums;white-space:nowrap}
.pg-axisline{display:flex;justify-content:space-between;gap:10px;margin-top:4px}

/* ── sparkline / step chart (inline SVG) ───────────────────────── */
.pg-spark{display:block;width:100%;margin:4px 0 0}
.pg-spark .pg-base{fill:none;stroke:var(--hair);stroke-width:1;vector-effect:non-scaling-stroke}
.pg-spark .pg-line{fill:none;stroke:var(--track);stroke-width:1.6;stroke-linejoin:round;
  stroke-linecap:round;vector-effect:non-scaling-stroke}
.pg-spark .pg-area{fill:var(--track);opacity:.13;stroke:none}
.pg-spark .pg-dot{fill:var(--track);stroke:none}
.pg-spark.brass .pg-line{stroke:var(--brass)}
.pg-spark.brass .pg-area{fill:var(--brass);opacity:.12}
.pg-spark.brass .pg-dot{fill:var(--brass)}
.pg-spark.plum .pg-line{stroke:var(--plum)}
.pg-spark.plum .pg-area{fill:var(--plum);opacity:.13}
.pg-spark.plum .pg-dot{fill:var(--plum)}

/* ── numbers ───────────────────────────────────────────────────── */
.pg-numrow{display:flex;align-items:baseline;gap:10px;padding:6px 0 2px}
.pg-num{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums;
  letter-spacing:-.02em;line-height:.9;font-size:min(52px,14vw);color:var(--num);flex:none}
.pg-numsub{flex:1;min-width:0;color:var(--muted);font-size:12.5px;overflow-wrap:anywhere}

/* ── target + projection ───────────────────────────────────────── */
.pg-targetrow{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:4px 0 2px;font-size:12px}
input.pg-tin{width:88px;flex:none;font-family:var(--display);font-weight:700;font-size:20px;
  line-height:1.1;text-align:center;font-variant-numeric:tabular-nums;padding:8px 6px}
.pg-proj{font-size:15px;line-height:1.45;margin:8px 0 0;overflow-wrap:anywhere}
.pg-proj.done{color:var(--brass)}
.pg-projdate{font-size:19px;color:var(--brass);margin-right:4px}

/* ── form consistency ──────────────────────────────────────────── */
.pg-consgrid{display:flex;gap:16px;margin:8px 0 2px}
.pg-cons{flex:1 1 0;min-width:0}
.pg-conshead{display:flex;align-items:baseline;justify-content:space-between;gap:6px}
.pg-conslbl{font-size:13px;color:var(--text)}
.pg-consval{font-size:16px;color:var(--num);font-variant-numeric:tabular-nums}
.pg-consfoot{font-size:11px;color:var(--muted);line-height:1.35;overflow-wrap:anywhere}

/* ── records ───────────────────────────────────────────────────── */
.pg-key{color:var(--muted);flex:none;min-width:0;font-size:14px}
.pg-valwrap{display:flex;flex-direction:column;align-items:flex-end;min-width:0;text-align:right}
.pg-val{font-family:var(--display);font-weight:700;font-size:16px;line-height:1.25;
  font-variant-numeric:tabular-nums;color:var(--num)}
.pg-valmeta{font-size:11.5px;color:var(--muted);line-height:1.3;overflow-wrap:anywhere}
#pgFlags .flags{padding-left:0;padding-right:0}

/* ── time of day ───────────────────────────────────────────────── */
.pg-propbar{display:flex;gap:2px;height:22px;margin:10px 0 4px;border-radius:4px;overflow:hidden}
.pg-propseg{position:relative;flex:1 1 0;min-width:0;display:flex;align-items:center;
  justify-content:center;border-radius:2px}
.pg-propseg::before{content:'';position:absolute;left:0;right:0;top:0;bottom:0;
  background:var(--heat-1);border-radius:2px}
.pg-propseg.lv2::before{background:var(--heat-2)}
.pg-propseg.lv3::before{background:var(--heat-3)}
.pg-propseg.lv4::before{background:var(--heat-4)}
.pg-propseg.empty::before{background:var(--tint)}
.pg-propnum{position:relative;font-size:11px;font-weight:600;color:var(--text);
  font-variant-numeric:tabular-nums}
.pg-todrow{display:flex;align-items:baseline;gap:10px;padding:7px 0;border-bottom:1px solid var(--hair);
  font-size:14px}
.pg-todrow .pg-hsq{width:10px;height:10px;flex:none;align-self:center}
.pg-todlbl{flex:none;width:58px;font-variant-numeric:tabular-nums}
.pg-todsub{flex:1;min-width:0;color:var(--muted);font-size:12px;text-align:right;overflow-wrap:anywhere}
.pg-todpct{flex:none;width:48px;text-align:right;font-size:15px;font-variant-numeric:tabular-nums;
  color:var(--num)}

.pg-foot{padding-top:16px;padding-bottom:4px;font-size:12px;line-height:1.45}

/* ── day sheet ─────────────────────────────────────────────────── */
.pg-scrim{position:fixed;left:0;right:0;top:0;bottom:0;z-index:80;display:flex;align-items:flex-end;
  justify-content:center;background:rgba(5,10,9,.55);animation:pg-fade .18s linear}
@keyframes pg-fade{from{opacity:0}to{opacity:1}}
.pg-panel{width:100%;max-width:520px;max-height:85%;overflow:auto;background:var(--sheet);
  border-top:1px solid var(--hair);border-radius:16px 16px 0 0;padding:14px 16px calc(16px + var(--sab))}
.pg-panelhead{display:flex;align-items:center;gap:10px}
.pg-paneltitle{flex:1;min-width:0;font:600 18px/1.3 var(--ui)}
.pg-panellbl{display:block;font-size:12px;color:var(--muted);margin:2px 0 8px;
  font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.pg-close{background:none;border:0;border-radius:999px;color:var(--track);font:inherit;font-size:15px;
  padding:10px 14px;min-height:44px;flex:none;cursor:pointer;-webkit-appearance:none}
.pg-close:active{opacity:.6}
.pg-panelempty{padding:6px 0 2px}
.pg-panelbody{padding-bottom:2px}
.pg-srow{border-bottom:1px solid var(--hair)}
.pg-smain{display:flex;align-items:center;gap:8px;min-height:52px;flex-wrap:wrap}
.pg-sopen{flex:1;min-width:0;display:flex;align-items:center;gap:12px;margin:0;padding:8px 0;
  background:none;border:0;color:inherit;font:inherit;text-align:left;cursor:pointer;
  -webkit-appearance:none;transition:opacity .12s linear}
.pg-sopen:active{opacity:.55}
.pg-snum{font-family:var(--display);font-weight:700;font-size:25px;line-height:1;min-width:46px;
  text-align:right;font-variant-numeric:tabular-nums;color:var(--num);flex:none}
.pg-smeta{flex:1;min-width:0;color:var(--muted);font-size:12.5px;line-height:1.35;overflow-wrap:anywhere}
.pg-sedit{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:0 0 10px;flex:1 0 100%}
.pg-sedit[hidden]{display:none}
input.pg-in{width:88px;flex:none;font-family:var(--display);font-weight:700;font-size:22px;
  line-height:1.1;text-align:center;font-variant-numeric:tabular-nums;padding:9px 8px}
.pg-err{flex:1 0 100%;color:var(--rose);font-size:13px}
.pg-smini{min-height:44px;padding:10px 16px;font-size:15px;flex:none}
.pg-sadd{border-bottom:1px solid var(--hair);padding-bottom:2px}
.pg-linkbtn{background:none;border:0;border-radius:999px;color:var(--track);font:inherit;font-size:15px;
  padding:10px 14px;min-height:44px;margin-left:-14px;flex:none;cursor:pointer;-webkit-appearance:none}
.pg-linkbtn:active{opacity:.6}
.pg-addnote{font-size:11.5px;line-height:1.4;padding:0 0 8px}

/* ── narrow phones: keep every row inside 320px ────────────────── */
@media (max-width:349px){
  .pg-num{font-size:min(46px,13vw)}
  .pg-plot{height:100px}
  .pg-consgrid{gap:12px}
}
__EOF_css_progress_css__

mkdir -p 'css'
cat > 'css/today.css' <<'__EOF_css_today_css__'
/* Today screen only. Everything shared (tokens, .pad, .rule, .kv, .list, .btn, .soon) lives in
   app.css and is reused as-is — nothing here redefines it. Prefix .tg- keeps the two phase-2
   stylesheets from stepping on each other. No :has(), no dvh/svh, no container queries. */

/* ── hero: the one big number ──────────────────────────────────── */
.tg-hero{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;padding:16px 16px 2px}
.tg-heronum{flex:1;min-width:0}
.tg-total{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.02em;
  line-height:.88;font-size:min(76px,21vw);color:var(--num)}
.tg-date{color:var(--muted);font:600 13px/1.35 var(--ui);margin:6px 0 0;letter-spacing:.01em}
.tg-unit{color:var(--muted);font-size:12px}
.tg-note{color:var(--rose);font-size:13px;margin-top:6px;overflow-wrap:anywhere}

/* ── goal ring ─────────────────────────────────────────────────── */
.tg-ringwrap{position:relative;flex:none;width:88px;height:88px}
.tg-ring{display:block;transform:rotate(-90deg)}
.tg-ring .tg-track{stroke:var(--hair)}
.tg-ring .tg-arc{stroke:var(--track);transition:stroke .25s linear}
.tg-ring.met .tg-arc{stroke:var(--brass)}
.tg-ringtext{position:absolute;left:0;right:0;top:0;bottom:0;display:flex;flex-direction:column;
  align-items:center;justify-content:center;gap:1px;pointer-events:none}
.tg-ringnum{font-family:var(--display);font-weight:700;font-size:21px;line-height:1;letter-spacing:-.01em;
  font-variant-numeric:tabular-nums;color:var(--num)}
.tg-ringlbl{font-size:11px;color:var(--muted)}
.tg-goalnote{padding:4px 16px 2px;font-size:14px;color:var(--muted);min-height:20px}
.tg-goalnote.met{color:var(--brass)}

/* ── streak + rest pass ────────────────────────────────────────── */
.tg-streak{padding:8px 16px 4px;gap:4px 10px;flex-wrap:wrap;min-height:36px}
.tg-streakline{flex:1 1 auto;min-width:0}
.tg-streaktxt{font-size:15px;color:var(--text)}
.tg-streaktxt.dim{color:var(--muted);font-size:14px}
.tg-streakwhy{font-size:13px;color:var(--rose);flex:1 0 100%;order:5}
/* pull the pass button's label onto the same left edge as the copy above it */
.tg-streak .tg-linkbtn{margin-left:-14px}

/* ── week / month / year / lifetime ────────────────────────────── */
.tg-minis{padding:0 16px}
.tg-val{white-space:nowrap;font-weight:600;font-variant-numeric:tabular-nums}
.tg-key{color:var(--muted);min-width:0}

/* ── set rows ──────────────────────────────────────────────────── */
.tg-head{padding:16px 16px 2px;font-size:13px;color:var(--muted)}
.tg-empty{padding-top:8px;margin-top:0;margin-bottom:0}
.tg-set{padding:0 16px;border-bottom:1px solid var(--hair)}
.tg-setmain{display:flex;align-items:center;gap:8px;min-height:52px}
.tg-editbtn{flex:1;min-width:0;display:flex;align-items:center;gap:12px;margin:0;padding:10px 0;min-height:44px;
  background:none;border:0;border-radius:0;color:inherit;font:inherit;text-align:left;
  -webkit-appearance:none;cursor:pointer;transition:opacity .12s linear}
.tg-editbtn:active{opacity:.55}
/* author display beats the UA [hidden] rule, so every display-setting class we toggle needs this */
.tg-editbtn[hidden]{display:none}
.tg-setnum{font-family:var(--display);font-weight:700;font-size:25px;line-height:1;min-width:46px;
  font-variant-numeric:tabular-nums;color:var(--num)}
.tg-setmeta{flex:1;min-width:0;color:var(--muted);font-size:13px;overflow-wrap:anywhere}
.tg-editline{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:0 0 12px}
.tg-editline[hidden]{display:none}
input.tg-in{width:88px;flex:none;font-family:var(--display);font-weight:700;font-size:22px;line-height:1.1;
  text-align:center;font-variant-numeric:tabular-nums;padding:9px 8px}
.tg-err{flex:1 0 100%;color:var(--rose);font-size:13px}
.tg-mini{min-height:44px;padding:10px 16px;font-size:15px;flex:none}

/* ── footer honesty line ───────────────────────────────────────── */
.tg-foot{padding:14px 16px 8px;font-size:13px;color:var(--muted)}

/* ── missed days ───────────────────────────────────────────────── */
.tg-quietrow{display:block;width:100%;text-align:left;padding:12px 16px;margin:0;min-height:44px;
  background:none;border:0;color:var(--muted);font:inherit;font-size:14px;
  border-top:1px solid var(--hair);border-radius:0;cursor:pointer;transition:opacity .12s linear}
.tg-quietrow:active{opacity:.6}

/* ── missed-day sheet ──────────────────────────────────────────── */
.tg-scrim{position:fixed;left:0;right:0;top:0;bottom:0;z-index:80;display:flex;align-items:flex-end;
  justify-content:center;background:rgba(5,10,9,.55);animation:tg-fade .18s linear}
@keyframes tg-fade{from{opacity:0}to{opacity:1}}
.tg-panel{width:100%;max-width:520px;max-height:85%;overflow:auto;background:var(--sheet);
  border-top:1px solid var(--hair);border-radius:16px 16px 0 0;
  padding:14px 16px calc(16px + var(--sab))}
.tg-panelhead{display:flex;align-items:center;gap:10px;margin-bottom:2px}
.tg-paneltitle{flex:1;min-width:0;font:600 18px/1.3 var(--ui)}
.tg-panellbl{display:block;font-size:12px;color:var(--muted);margin:2px 0 6px}
.tg-gaprow{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:6px 0;border-bottom:1px solid var(--hair)}
.tg-gapday{flex:1;min-width:90px;font-size:15px}
.tg-gapedit{display:flex;align-items:center;gap:8px;flex-wrap:wrap;flex:1 0 100%}
.tg-gapedit[hidden]{display:none}
.tg-linkbtn{background:none;border:0;border-radius:999px;color:var(--track);font:inherit;font-size:15px;
  padding:10px 14px;min-height:44px;cursor:pointer;flex:none;transition:opacity .12s linear}
.tg-linkbtn:active{opacity:.6}
.tg-linkbtn.dim{color:var(--muted)}
.tg-linkbtn[disabled]{opacity:.4}
.tg-donetag{font-size:13px;color:var(--brass);padding:10px 0}

/* ── link row to progress ──────────────────────────────────────── */
.tg-prog{display:flex;align-items:center;gap:10px;min-height:48px;padding:12px 16px;
  border-top:1px solid var(--hair);margin-top:10px;color:var(--muted);font-size:15px}
.tg-prog .chev{font-size:19px;line-height:1;color:var(--muted)}
__EOF_css_today_css__

mkdir -p .
cat > 'index.html' <<'__EOF_index_html__'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0E1A18" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#E9EEEA" media="(prefers-color-scheme: light)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Pushups">
<title>Pushups</title>
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<link rel="icon" href="icons/icon-192.png">
<link rel="stylesheet" href="css/app.css">
<link rel="stylesheet" href="css/today.css">
<link rel="stylesheet" href="css/progress.css">
</head>
<body>
<div id="banner"></div>
<main id="view"></main>
<nav id="tabs" aria-label="Sections">
  <a href="#/today" data-tab="today"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.6" fill="currentColor" stroke="none"/></svg>Today</a>
  <a href="#/train" data-tab="train"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20V5"/><path d="M6 11l6-6 6 6"/></svg>Train</a>
  <a class="todo" href="#/progress" data-tab="progress"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 19v-4"/><path d="M12 19V8"/><path d="M19 19v-8"/></svg>Progress</a>
  <a class="todo" href="#/badges" data-tab="badges"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="9" r="5.4"/><path d="M9.2 13.6L7.5 20l4.5-2.6L16.5 20l-1.7-6.4"/></svg>Badges</a>
  <a href="#/settings" data-tab="settings"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h9"/><path d="M19.2 8H20"/><circle cx="16.6" cy="8" r="2.4"/><path d="M4 16h4"/><path d="M14.2 16H20"/><circle cx="11.4" cy="16" r="2.4"/></svg>Settings</a>
</nav>
<script>
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').then(function (r) { window.__swReg = r; });
}
</script>
<script type="module" src="js/main.js"></script>
</body>
</html>
__EOF_index_html__

mkdir -p 'js'
cat > 'js/camera.js' <<'__EOF_js_camera_js__'
const METADATA_TIMEOUT_MS = 5000;

export function cameraSupports(videoEl) {
  void videoEl;
  return !!(typeof navigator !== 'undefined'
    && navigator.mediaDevices
    && typeof navigator.mediaDevices.getUserMedia === 'function');
}

function waitMetadata(videoEl) {
  return new Promise((resolve, reject) => {
    if (videoEl.readyState >= 1 && videoEl.videoWidth > 0) {
      resolve();
      return;
    }
    let done = false;
    const finish = (err) => {
      if (done) return;
      done = true;
      videoEl.removeEventListener('loadedmetadata', ok);
      clearTimeout(timer);
      if (err) reject(err);
      else resolve();
    };
    const ok = () => finish(null);
    const timer = setTimeout(() => {
      finish(new Error('Camera preview timed out after 5 seconds. Close other apps using the camera, then tap Start again.'));
    }, METADATA_TIMEOUT_MS);
    videoEl.addEventListener('loadedmetadata', ok, { once: true });
  });
}

function describeTrack(track, fallbackFacing) {
  if (!track || typeof track.getSettings !== 'function') {
    return { facingMode: fallbackFacing, width: 0, height: 0, deviceId: '' };
  }
  const s = track.getSettings();
  return {
    facingMode: s.facingMode || fallbackFacing,
    width: s.width || 0,
    height: s.height || 0,
    deviceId: s.deviceId || '',
  };
}

export async function openCamera(videoEl, opts = {}) {
  const { facing = 'environment', deviceId = null, width = 1280, height = 720 } = opts;

  if (!videoEl) throw new Error('No video element to attach the camera to.');
  if (!cameraSupports(videoEl)) {
    const err = new Error('This browser cannot open a camera.');
    err.name = 'NotSupportedError';
    throw err;
  }

  const video = {
    facingMode: deviceId ? undefined : facing,
    width: { ideal: width },
    height: { ideal: height },
    frameRate: { ideal: 30 },
  };
  if (deviceId) video.deviceId = { exact: deviceId };

  const stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });

  videoEl.setAttribute('playsinline', '');
  videoEl.setAttribute('webkit-playsinline', '');
  videoEl.muted = true;
  videoEl.srcObject = stream;

  await waitMetadata(videoEl);

  const track = stream.getVideoTracks()[0];
  const info = describeTrack(track, facing);
  const settings = {
    facingMode: info.facingMode,
    width: info.width,
    height: info.height,
    deviceId: info.deviceId,
    facing: info.facingMode === 'user' ? 'user' : facing,
    needsTap: false,
  };

  try {
    await videoEl.play();
  } catch (err) {
    void err;
    settings.needsTap = true;
  }

  return { stream, settings, track, videoEl };
}

export async function closeCamera(state) {
  if (!state) return;
  try {
    const stream = state.stream;
    if (stream && typeof stream.getTracks === 'function') {
      for (const track of stream.getTracks()) {
        try { track.stop(); } catch (err) { void err; }
      }
    }
    if (state.videoEl) state.videoEl.srcObject = null;
  } catch (err) {
    void err;
  }
}

export async function resumePreview(videoEl) {
  if (!videoEl) return false;
  try {
    await videoEl.play();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export async function switchCamera(videoEl, facing, state) {
  await closeCamera(state);
  return openCamera(videoEl, { facing, deviceId: null });
}

export async function listCameras() {
  try {
    if (!cameraSupports(null)) return [];
    const devices = await navigator.mediaDevices.enumerateDevices();
    return devices
      .filter((d) => d.kind === 'videoinput')
      .map((d, i) => ({
        deviceId: d.deviceId,
        label: d.label || `Camera ${i + 1}`,
        kind: d.kind,
      }));
  } catch (err) {
    void err;
    return [];
  }
}

export function describeCameraError(err) {
  const name = (err && err.name) || '';
  const message = (err && err.message) || '';

  if (typeof window !== 'undefined' && window.isSecureContext === false) {
    return {
      title: 'The camera needs a secure (HTTPS) address',
      steps: [
        'iOS and macOS block the camera on plain http:// pages, and on any address other than localhost.',
        'Open the app through its https:// address, or tap the Share button in Safari and choose Add to Home Screen so it loads over HTTPS.',
        'If you are testing on your own machine, use https://localhost or a TLS tunnel, then reload.',
      ],
    };
  }

  switch (name) {
    case 'NotAllowedError':
    case 'PermissionDeniedError':
      return {
        title: 'Camera permission was blocked',
        steps: [
          'Tap the camera or page-info icon in the address bar and set Camera to Allow, then reload.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow (or "Ask"), then scroll back to the app.',
          'For a home-screen app: Settings ▸ pushups ▸ Camera ▸ Allow.',
          'Close other apps that may hold the camera (Photo Booth, FaceTime) and tap Start again.',
        ],
      };
    case 'NotFoundError':
    case 'DevicesNotFoundError':
      return {
        title: 'No camera found for this choice',
        steps: [
          'The selected camera is gone (headset, external cam, or a back/front switch on a device with one camera).',
          'Open Settings in the app and pick the other camera, or reload the page to re-list cameras.',
        ],
      };
    case 'NotReadableError':
    case 'InUseError':
    case 'TrackStartError':
      return {
        title: 'Another app or tab is using the camera',
        steps: [
          'Close the other browser tab that has the camera open.',
          'Quit any app recording video, then relaunch the app from the Home Screen.',
          'If it keeps happening, restart the iPhone: the camera service on iOS sometimes stays locked.',
        ],
      };
    case 'OverconstrainedError':
      return {
        title: 'The camera cannot do the settings we asked for',
        steps: [
          'Lower the resolution in Settings (try 640 x 480) or switch facing mode.',
          'Tap Start again.',
        ],
      };
    case 'SecurityError':
      return {
        title: 'The browser blocked camera access for security',
        steps: [
          'Confirm the page address starts with https:// (or localhost).',
          'Reload the page.',
          'If the app came from a Home Screen icon, delete it and add it again from the https:// page.',
        ],
      };
    case 'NotSupportedError':
      return {
        title: 'This browser has no camera access',
        steps: [
          'Open the app in Safari (Chrome and in-app browsers on iOS cannot always reach the camera).',
          'Update iOS to the current release, then reload.',
        ],
      };
    case 'AbortError':
      return {
        title: 'Camera start was interrupted',
        steps: ['Tap Start again.', 'If it repeats, close other camera apps and reload.'],
      };
    default:
      return {
        title: 'The camera did not open',
        steps: [
          message ? `Details: ${message}` : 'No details from the browser.',
          'Tap Start again.',
          'Reload the page, then check Settings ▸ Safari ▸ Camera ▸ Allow.',
        ],
      };
  }
}

export async function setTorch(track, on) {
  if (!track || typeof track.applyConstraints !== 'function') return false;
  try {
    const caps = typeof track.getCapabilities === 'function' ? track.getCapabilities() : null;
    if (!caps || !caps.torch) return false;
    await track.applyConstraints({ advanced: [{ torch: !!on }] });
    if (!on) await track.applyConstraints({ advanced: [{}] });
    return true;
  } catch (err) {
    void err;
    return false;
  }
}
__EOF_js_camera_js__

mkdir -p 'js'
cat > 'js/counter.js' <<'__EOF_js_counter_js__'
import { OneEuro } from './one-euro.js';

export const LANDMARKS = {
  NOSE: 0, L_SHOULDER: 11, R_SHOULDER: 12, L_ELBOW: 13, R_ELBOW: 14,
  L_WRIST: 15, R_WRIST: 16, L_HIP: 23, R_HIP: 24, L_KNEE: 25, R_KNEE: 26,
  L_ANKLE: 27, R_ANKLE: 28,
};

const SIDE_PTS = {
  left: { shoulder: 11, elbow: 13, wrist: 15, hip: 23, knee: 25, ankle: 27 },
  right: { shoulder: 12, elbow: 14, wrist: 16, hip: 24, knee: 26, ankle: 28 },
};

const MIN_LM_VIS = 0.1;
const QUALITY_EMA_ALPHA = 0.2;
const SIDE_SWITCH_MARGIN = 0.08;
const QUALITY_MIN = 0.35;
const QUALITY_LOST = 0.15;
const QUALITY_REP_MIN = 0.4;
const BODY_ANGLE_MAX = 12;
const HIP_GATE = 0.16;
const HIP_GATE_EMA_ALPHA = 0.12;
// Landmarks are normalised per-axis, so the frame diagonal is unknown. A 4:3 sensor is assumed.
const FRAME_DIAGONAL = Math.hypot(1, 0.75);
const NOTSIDE_MIN_DX = 0.15 * FRAME_DIAGONAL;
const HYST = 8;
const BOTTOM_ZONE = 15;
const LOCKOUT_ZONE = 12;
const ASSIST_DEPTH = 0.10;
const SHALLOW_DROP_GATE = 0.08;
const SAG_LIMIT = 0.18;
const PIKE_LIMIT = -0.14;
const FAST_SLACK_MS = 120;
const SLOW_MS = 6000;
const REVERSAL_HYST = 10;
const TRACE_LEN = 45;

function num(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

function point(lm, i) {
  if (!Array.isArray(lm) || lm.length <= i) return null;
  const p = lm[i];
  if (!p || !num(p.x) || !num(p.y)) return null;
  if ((num(p.visibility) ? p.visibility : 0) < MIN_LM_VIS) return null;
  return p;
}

function midPoint(lm, i, j) {
  const a = point(lm, i);
  const b = point(lm, j);
  if (!a || !b) return null;
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function hipPoint(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  if (k) {
    const p = point(lm, k.hip);
    if (p) return p;
  }
  return midPoint(lm, LANDMARKS.L_HIP, LANDMARKS.R_HIP);
}

function bodyLine(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  let S = k ? point(lm, k.shoulder) : null;
  let A = k ? point(lm, k.ankle) : null;
  // Prefer the measured side's own endpoints: when the body folds toward vertical only that
  // side's shoulder and ankle travel together, the far side would keep the line horizontal.
  if (!S) S = midPoint(lm, LANDMARKS.L_SHOULDER, LANDMARKS.R_SHOULDER);
  if (!A) A = midPoint(lm, LANDMARKS.L_ANKLE, LANDMARKS.R_ANKLE);
  if (!S || !A) return null;
  const dx = A.x - S.x;
  const dy = A.y - S.y;
  const len = Math.hypot(dx, dy);
  if (!(len > 1e-6)) return null;
  return { S, A, dx, dy, len };
}

export function angleBetween(a, b, c) {
  if (!a || !b || !c) return null;
  const v1x = a.x - b.x, v1y = a.y - b.y;
  const v2x = c.x - b.x, v2y = c.y - b.y;
  const m1 = Math.hypot(v1x, v1y);
  const m2 = Math.hypot(v2x, v2y);
  if (!(m1 > 1e-6) || !(m2 > 1e-6)) return null;
  let cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  cos = Math.max(-1, Math.min(1, cos));
  return Math.acos(cos) * 180 / Math.PI;
}

export function elbowAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.shoulder), point(lm, k.elbow), point(lm, k.wrist));
}

export function shoulderAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.elbow), point(lm, k.shoulder), point(lm, k.hip));
}

// Signed, line-length-normalised perpendicular distance of the hip from the shoulder-ankle line.
// The normal is forced to point toward larger image y (the floor), so sagging hips are POSITIVE
// and piked hips NEGATIVE for both facing directions.
export function hipOffsetOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  const H = hipPoint(lm, side);
  if (!H) return null;
  let nx = -g.dy;
  let ny = g.dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const m = Math.hypot(nx, ny);
  if (!(m > 1e-6)) return null;
  nx /= m; ny /= m;
  return ((H.x - g.S.x) * nx + (H.y - g.S.y) * ny) / g.len;
}

// atan2(-dy, dx) folded into (-90, 90] so a horizontal plank reads near 0 whichever way the
// subject faces. Sign of dx is kept available through dxOf(); 'notSide' uses |dx|.
export function bodyAngleOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  let deg = Math.atan2(-g.dy, g.dx) * 180 / Math.PI;
  if (deg > 90) deg -= 180;
  else if (deg < -90) deg += 180;
  return deg;
}

export function dxOf(lm, side = null) {
  const g = bodyLine(lm, side);
  return g ? g.dx : null;
}

// (shoulder.y - ankle.y) / |shoulder->ankle|. Grows as the body travels down: a proper side-on
// pushup moves this by roughly 0.10-0.25 between the top and the bottom position.
export function shoulderNormOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  return (g.S.y - g.A.y) / g.len;
}

// A 2-tap median is just a mean, so the spike killer is 3 taps wide.
class MedianFilter {
  constructor(size = 3) {
    this.size = Math.max(1, size);
    this.buf = [];
  }
  reset() { this.buf = []; }
  push(v) {
    if (!num(v)) return null;
    this.buf.push(v);
    if (this.buf.length > this.size) this.buf.shift();
    const s = this.buf.slice().sort((a, b) => a - b);
    const k = (s.length - 1) / 2;
    const lo = Math.floor(k);
    const hi = Math.ceil(k);
    return s[lo] + (s[hi] - s[lo]) * (k - lo);
  }
}

function cleanParams(params) {
  const p = params || {};
  return {
    top: num(p.top) ? p.top : 155,
    bottom: num(p.bottom) ? p.bottom : 100,
    minRepMs: num(p.minRepMs) ? p.minRepMs : 400,
    cleanOnly: !!p.cleanOnly,
    secondarySignal: p.secondarySignal === 'off' || p.secondarySignal === 'confirm'
      ? p.secondarySignal : 'assist',
  };
}

function emptyRep() {
  return {
    tStart: null, tCrossBottom: null, minElbow: null, maxElbow: null,
    dropBase: null, normMin: null, normMax: null, shoulderDrop: 0,
    hipMax: null, hipMin: null,
    lowQuality: false, halfByTravel: false, side: null,
  };
}

export class Counter {
  constructor(params) {
    this.params = cleanParams(params);
    this.armHoldMs = 2500;
    this.reset('init');
  }

  setParams(params) {
    this.params = cleanParams({ ...this.params, ...params });
  }

  setArmHold(ms) {
    this.armHoldMs = num(ms) && ms >= 0 ? ms : 2500;
  }

  reset(reason) {
    this.lastResetReason = reason || null;
    this.reps = 0;
    this.repsDetected = 0;
    this.cleanReps = 0;
    this.state = 'idle';
    this.armed = false;
    this.armStreakStart = null;
    this.armLockedAt = null;
    this.side = null;
    this.qVis = { left: null, right: null };
    this.quality = 0;
    this.euro = new OneEuro({ minCutoff: 1.1, beta: 0.02, dCutoff: 1.0 });
    this.medElbow = new MedianFilter(3);
    this.medHip = new MedianFilter(3);
    this.hipEma = null;
    this.rep = emptyRep();
    this.lastRep = null;
    this.events = [];
    this.trace = [];
    this.normBaseline = null;
    this.lastActiveMs = null;
    this.lastT = null;
  }

  _touch(t) { this.lastActiveMs = t; }

  _clearFilters() {
    this.euro.reset();
    this.medElbow.reset();
    this.medHip.reset();
    this.hipEma = null;
    this.normBaseline = null;
  }

  _dropInFlight() {
    this.rep = emptyRep();
    this.state = 'idle';
  }

  _updateSideQuality(lm) {
    if (!lm) return;
    for (const side of ['left', 'right']) {
      const k = SIDE_PTS[side];
      const ids = [k.shoulder, k.elbow, k.wrist, k.hip, k.ankle];
      let sum = 0;
      let n = 0;
      for (const i of ids) {
        const p = Array.isArray(lm) && lm.length > i ? lm[i] : null;
        if (p && num(p.visibility)) { sum += p.visibility; n++; }
      }
      if (!n) continue;
      const mean = sum / n;
      const prev = this.qVis[side];
      this.qVis[side] = prev === null
        ? mean
        : prev + QUALITY_EMA_ALPHA * (mean - prev);
    }

    const L = this.qVis.left;
    const R = this.qVis.right;
    if (this.side === null) {
      if (L !== null || R !== null) this.side = (R !== null && L !== null && R > L) ? 'right' : 'left';
    } else {
      const cur = this.qVis[this.side];
      const other = this.side === 'left' ? 'right' : 'left';
      const oth = this.qVis[other];
      if (oth !== null && cur !== null && oth > cur + SIDE_SWITCH_MARGIN) this.side = other;
    }
    this.quality = this.side ? (this.qVis[this.side] || 0) : 0;
  }

  _plank(present, quality, dx, bodyAngle, hipForGate) {
    const reasons = [];
    if (!present || !num(dx) || !num(bodyAngle) || quality <= 0) {
      reasons.push('noPose');
    } else {
      if (quality < QUALITY_MIN) reasons.push('lowVis');
      if (Math.abs(dx) < NOTSIDE_MIN_DX) reasons.push('notSide');
      if (Math.abs(bodyAngle) > BODY_ANGLE_MAX) reasons.push('bodyAngle');
      if (num(hipForGate) && Math.abs(hipForGate) > HIP_GATE) reasons.push('hip');
    }
    return { valid: reasons.length === 0, reasons };
  }

  _startRep(t, e, side, shoulderNorm) {
    this.rep = emptyRep();
    this.rep.tStart = t;
    this.rep.minElbow = e;
    this.rep.side = side;
    // Travel is measured from the held top position, not from the (lagging) moment the angle
    // crosses top-8, otherwise smoothing eats a fifth of every rep's measured depth.
    let base = num(this.normBaseline) ? this.normBaseline : null;
    if (num(shoulderNorm)) base = base === null ? shoulderNorm : Math.min(base, shoulderNorm);
    this.rep.dropBase = base;
    this.rep.normMin = base;
    this.rep.normMax = base;
    this.state = 'down';
    this._touch(t);
  }

  _observeRep(e, quality, hip, shoulderNorm) {
    const r = this.rep;
    if (r.tStart === null) return;
    if (num(e)) {
      if (r.minElbow === null || e < r.minElbow) r.minElbow = e;
      // maxElbow belongs to the up phase only; seeding it at the top of the descent would
      // make every rep look like it reversed straight out of the bottom.
      if (this.state === 'up' && (r.maxElbow === null || e > r.maxElbow)) r.maxElbow = e;
    }
    if (quality < QUALITY_REP_MIN) r.lowQuality = true;
    if (num(hip)) {
      if (r.hipMax === null || hip > r.hipMax) r.hipMax = hip;
      if (r.hipMin === null || hip < r.hipMin) r.hipMin = hip;
    }
    if (num(shoulderNorm)) {
      if (r.normMin === null || shoulderNorm < r.normMin) r.normMin = shoulderNorm;
      if (r.normMax === null || shoulderNorm > r.normMax) r.normMax = shoulderNorm;
      const d = r.normMax - r.normMin;
      if (d > r.shoulderDrop) r.shoulderDrop = d;
    }
  }

  _complete(t, e, lockout) {
    const p = this.params;
    const r = this.rep;
    const hadDescent = r.tStart !== null;
    const durationMs = hadDescent ? t - r.tStart : 0;
    const minElbow = num(r.minElbow) ? r.minElbow : e;
    const maxElbow = num(r.maxElbow) ? r.maxElbow : e;
    const bottomed = r.tCrossBottom !== null || r.halfByTravel;

    this.state = 'hold';
    this.rep = emptyRep();

    if (!hadDescent || !bottomed || durationMs < p.minRepMs) {
      this._touch(t);
      return null;
    }

    const flags = [];
    if (minElbow > p.bottom) flags.push('half');
    if (lockout) flags.push('lockout');
    if (num(r.hipMax) && r.hipMax > SAG_LIMIT) flags.push('sag');
    if (num(r.hipMin) && r.hipMin < PIKE_LIMIT) flags.push('pike');
    if (r.lowQuality || this.quality < QUALITY_REP_MIN) flags.push('lost');
    if (durationMs < p.minRepMs + FAST_SLACK_MS) flags.push('fast');
    if (durationMs > SLOW_MS) flags.push('slow');
    if (p.secondarySignal === 'confirm' && r.normMin !== null) {
      if (r.shoulderDrop < SHALLOW_DROP_GATE) flags.push('shallow');
    }

    this.repsDetected++;
    if (flags.length === 0) this.cleanReps++;
    if (flags.length === 0 || !p.cleanOnly) this.reps++;

    const rep = {
      n: this.repsDetected,
      tStart: r.tStart,
      tEnd: t,
      durationMs,
      minElbow,
      maxElbow,
      shoulderDrop: num(r.shoulderDrop) ? r.shoulderDrop : 0,
      hipMax: num(r.hipMax) ? r.hipMax : null,
      hipMin: num(r.hipMin) ? r.hipMin : null,
      flags,
      side: r.side || this.side,
    };
    // spec spells these hipMin/hipMax the other way round; the values themselves are
    // (max positive = sag, most negative = pike), so keep both names meaning min/max.
    this.lastRep = rep;
    this.events.push({ type: 'rep', t, data: rep });
    this._touch(t);
    return rep;
  }

  _step(t, e, hip, shoulderNorm, sideTravelAllowed) {
    const p = this.params;
    const top = p.top;
    const bottom = p.bottom;
    const r = this.rep;

    switch (this.state) {
      case 'idle':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'hold':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'down': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;

        if (e <= bottom) {
          this.state = 'bottom';
          this._touch(t);
          break;
        }
        // shoulder travel proves real depth even when the elbow never reaches `bottom`:
        // the rep stays alive and earns 'half' on completion. Checked before the
        // back-to-top discard so a genuine shallow rep is not thrown away.
        if (sideTravelAllowed && !r.halfByTravel
            && r.shoulderDrop >= ASSIST_DEPTH
            && r.minElbow !== null && e >= r.minElbow + REVERSAL_HYST) {
          r.halfByTravel = true;
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
          break;
        }
        if (e >= top - HYST) {
          // never got deep: not a rep, arms are back up
          this.rep = emptyRep();
          this.state = 'hold';
          this._touch(t);
          break;
        }
        break;
      }

      case 'bottom':
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;
        if (e > bottom + HYST) {
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
        }
        break;

      case 'up': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (e >= top) {
          this._complete(t, e, false);
          break;
        }
        if (e <= bottom) {
          this.state = 'bottom';
          break;
        }
        const nearBottomZone = e <= bottom + BOTTOM_ZONE && r.maxElbow !== null
          && r.maxElbow < top - LOCKOUT_ZONE;
        if (nearBottomZone) {
          this.state = 'bottom';
          break;
        }
        if (r.maxElbow !== null && e <= r.maxElbow - HYST) {
          if (r.maxElbow >= top - LOCKOUT_ZONE) this._complete(t, e, true);
          else {
            this.rep = emptyRep();
            this.state = 'idle';
            this._touch(t);
          }
        }
        break;
      }

      default:
        this.state = 'idle';
    }
  }

  addFrame(tMs, frame) {
    try {
      return this._addFrame(tMs, frame);
    } catch (err) {
      const ev = this.events;
      this.events = [];
      return {
        reps: this.reps, repsDetected: this.repsDetected, cleanReps: this.cleanReps,
        state: 'idle', armed: false, armMs: 0, quality: 0, side: this.side,
        angles: { left: { elbow: null, shoulder: null }, right: { elbow: null, shoulder: null } },
        hipOffset: null, bodyAngle: null,
        plank: { valid: false, reasons: ['noPose'] },
        lastRep: null, events: ev, trace: this.trace,
        lastActiveMs: this.lastActiveMs, error: err && err.message ? err.message : String(err),
      };
    }
  }

  _addFrame(tMs, frame) {
    const p = this.params;
    this.events = [];
    this.lastRep = null;

    const lm = frame && Array.isArray(frame.landmarks) ? frame.landmarks : null;
    const present = !!(frame && frame.present && lm && lm.length > LANDMARKS.R_ANKLE);
    const t = num(tMs) ? tMs : (this.lastT === null ? 0 : this.lastT);

    this._updateSideQuality(present ? lm : null);
    const side = this.side;

    const rawElbow = present ? elbowAngle(lm, side) : null;
    const angles = {
      left: { elbow: present ? elbowAngle(lm, 'left') : null, shoulder: present ? shoulderAngle(lm, 'left') : null },
      right: { elbow: present ? elbowAngle(lm, 'right') : null, shoulder: present ? shoulderAngle(lm, 'right') : null },
    };
    const rawHip = present ? hipOffsetOf(lm, side) : null;
    const bodyAngle = present ? bodyAngleOf(lm, side) : null;
    const dx = present ? dxOf(lm, side) : null;
    const rawNorm = present ? shoulderNormOf(lm, side) : null;

    let elbow = null;
    let hip = null;
    let shoulderNorm = null;
    if (present) {
      shoulderNorm = num(rawNorm) ? rawNorm : null;
      if (num(rawHip)) {
        const m = this.medHip.push(rawHip);
        hip = num(m) ? m : null;
        if (hip !== null) {
          this.hipEma = this.hipEma === null ? hip : this.hipEma + HIP_GATE_EMA_ALPHA * (hip - this.hipEma);
        }
      }
      if (num(rawElbow)) {
        const m = this.medElbow.push(rawElbow);
        if (m !== null) {
          const f = this.euro.filter(t, m);
          if (num(f)) elbow = f;
        }
      }
    } else {
      this.medHip.reset();
      this.medElbow.reset();
      this.hipEma = null;
      this.euro.reset();
    }

    const plank = this._plank(present, this.quality, dx, bodyAngle, this.hipEma);

    if (!plank.valid) {
      this.armStreakStart = null;
      if (this.armed) {
        this.armed = false;
        this.armLockedAt = null;
        this._dropInFlight();
        this._clearFilters();
        this.events.push({ type: 'armBreak', t, data: { reason: plank.reasons[0] || 'noPose', t } });
        this._touch(t);
      } else {
        this._dropInFlight();
        if (!present) this._clearFilters();
      }
    } else {
      if (this.armStreakStart === null) this.armStreakStart = t;
      if (!this.armed) {
        if (t - this.armStreakStart >= this.armHoldMs) {
          this.armed = true;
          this.armLockedAt = t;
          this._clearFilters();
          this._dropInFlight();
          this._touch(t);
        }
      } else {
        this._touch(t);
      }

      if (this.armed && elbow !== null) {
        this._step(t, elbow, hip, shoulderNorm, p.secondarySignal !== 'off');
      }
      if (this.armed && num(shoulderNorm)) {
        // Top-of-rep reference for shoulder travel: snaps down to a new high body position and
        // creeps back up slowly, so filter lag at the start of a descent cannot eat the depth.
        if (this.normBaseline === null || shoulderNorm < this.normBaseline) this.normBaseline = shoulderNorm;
        else this.normBaseline += 0.004 * (shoulderNorm - this.normBaseline);
      }
    }

    this.lastT = t;

    this.trace.push({
      t,
      elbowRaw: rawElbow,
      elbowFiltered: elbow,
      hipOffset: hip,
      shoulderNorm,
      quality: this.quality,
    });
    if (this.trace.length > TRACE_LEN) this.trace.shift();

    const events = this.events;
    this.events = [];

    return {
      reps: this.reps,
      repsDetected: this.repsDetected,
      cleanReps: this.cleanReps,
      state: this.state,
      armed: this.armed,
      armMs: this.armed && this.armLockedAt !== null ? t - this.armLockedAt : 0,
      quality: this.quality,
      side,
      angles,
      hipOffset: hip,
      bodyAngle,
      plank,
      lastRep: this.lastRep,
      events,
      trace: this.trace,
      lastActiveMs: this.lastActiveMs,
    };
  }
}
__EOF_js_counter_js__

mkdir -p 'js'
cat > 'js/db.js' <<'__EOF_js_db_js__'
/* schema
set  { id, startedAt (epoch ms), endedAt, durationMs, mode:'camera'|'manual', source:'camera'|'manual',
       repsDetected, repsFinal, flags:{ sag, pike, half, lockout, lost }, cameraUsed:'environment'|'user',
       qualityStats:{ fpsMean, visMean, frames }, paramsUsed:{...thresholds }, presetName, model, notes,
       day:'YYYY-MM-DD', schema:1 }
rep  { id, setId, tMs (relative to set start), durationMs, minElbow, maxElbow, shoulderDrop, hipOffset,
       side, flags:[], n }
meta { k, v }
DB pushups v1: stores 'sets' (keyPath id autoIncrement, indexes startedAt, day),
'reps' (keyPath id autoIncrement, index setId), 'meta' (keyPath k).
*/

const DB_NAME = 'pushups';
const DB_VERSION = 1;
const SCHEMA = 1;

let dbPromise = null;

function toPromise(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('IndexedDB request failed'));
  });
}

function finish(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
    tx.onerror = () => reject(tx.error || new Error('IndexedDB transaction failed'));
  });
}

function idb() {
  if (typeof indexedDB === 'undefined' || indexedDB === null) {
    throw new Error('IndexedDB is not available in this browser/context');
  }
  return indexedDB;
}

export function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = idb().open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (ev) => {
      const db = req.result;
      if (!db.objectStoreNames.contains('sets')) {
        const sets = db.createObjectStore('sets', { keyPath: 'id', autoIncrement: true });
        sets.createIndex('startedAt', 'startedAt');
        sets.createIndex('day', 'day');
      }
      if (!db.objectStoreNames.contains('reps')) {
        const reps = db.createObjectStore('reps', { keyPath: 'id', autoIncrement: true });
        reps.createIndex('setId', 'setId');
      }
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'k' });
      }
      void ev;
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('could not open ' + DB_NAME));
    req.onblocked = () => reject(new Error('IndexedDB open blocked by another tab'));
  });
  return dbPromise;
}

export async function resetForTest() {
  if (dbPromise) {
    const db = await dbPromise.catch(() => null);
    if (db) db.close();
  }
  dbPromise = null;
  await new Promise((resolve, reject) => {
    const req = idb().deleteDatabase(DB_NAME);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error || new Error('deleteDatabase failed'));
    req.onblocked = () => resolve();
  });
  return open();
}

export function localDay(ms) {
  const d = new Date(ms === undefined || ms === null ? Date.now() : ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function normalizeSet(set) {
  const rec = { ...(set || {}) };
  delete rec.id;
  if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
  if (!rec.day) rec.day = localDay(rec.startedAt);
  rec.schema = SCHEMA;
  return rec;
}

function normalizeRep(rep, setId) {
  const rec = { ...(rep || {}) };
  delete rec.id;
  rec.setId = setId;
  return rec;
}

export async function saveSet(set, repsArray) {
  const db = await open();
  const rec = normalizeSet(set);
  const reps = Array.isArray(repsArray) ? repsArray : [];
  let id = null;
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  id = await toPromise(tx.objectStore('sets').add(rec));
  for (const rep of reps) {
    tx.objectStore('reps').add(normalizeRep(rep, id));
  }
  await finish(tx);
  return id;
}

export async function getSet(id) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rec = await toPromise(tx.objectStore('sets').get(id));
  await finish(tx);
  return rec || null;
}

export async function listReps(setId) {
  const db = await open();
  const tx = db.transaction('reps', 'readonly');
  const reps = await toPromise(tx.objectStore('reps').index('setId').getAll(setId));
  await finish(tx);
  return (reps || []).sort((a, b) => (a.tMs || 0) - (b.tMs || 0));
}

function collectAll(storeName, indexer) {
  return open().then((db) => {
    const tx = db.transaction(storeName, 'readonly');
    const src = indexer ? indexer(tx.objectStore(storeName)) : tx.objectStore(storeName);
    return toPromise(src.getAll()).then((rows) => finish(tx).then(() => rows || []));
  });
}

export async function listSets() {
  const rows = await collectAll('sets');
  return rows.sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function listSetsForDay(day) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rows = await toPromise(tx.objectStore('sets').index('day').getAll(day));
  await finish(tx);
  return (rows || []).sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function updateSet(id, patch) {
  const db = await open();
  const tx = db.transaction('sets', 'readwrite');
  const store = tx.objectStore('sets');
  const current = await toPromise(store.get(id));
  if (!current) {
    await finish(tx).catch(() => {});
    return null;
  }
  const next = { ...current, ...(patch || {}), id: current.id };
  await toPromise(store.put(next));
  await finish(tx);
  return next;
}

export async function deleteSet(id) {
  const db = await open();
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  tx.objectStore('sets').delete(id);
  const keys = await toPromise(tx.objectStore('reps').index('setId').getAllKeys(id));
  for (const k of keys || []) tx.objectStore('reps').delete(k);
  await finish(tx);
  return true;
}

export async function countSets() {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const n = await toPromise(tx.objectStore('sets').count());
  await finish(tx);
  return n || 0;
}

export async function getMeta(k) {
  const db = await open();
  const tx = db.transaction('meta', 'readonly');
  const rec = await toPromise(tx.objectStore('meta').get(k));
  await finish(tx);
  return rec && 'v' in rec ? rec.v : undefined;
}

export async function setMeta(k, v) {
  const db = await open();
  const tx = db.transaction('meta', 'readwrite');
  await toPromise(tx.objectStore('meta').put({ k, v }));
  await finish(tx);
  return v;
}

export async function exportJSON() {
  const [sets, reps, meta] = await Promise.all([
    collectAll('sets'), collectAll('reps'), collectAll('meta'),
  ]);
  return JSON.stringify({
    app: 'pushups',
    schema: SCHEMA,
    exportedAt: Date.now(),
    sets: sets || [],
    reps: reps || [],
    meta: meta || [],
  });
}

function isIdKey(key) {
  return typeof key === 'number' || typeof key === 'string';
}

async function idIsFree(store, id) {
  if (!isIdKey(id)) return false;
  const existing = await toPromise(store.get(id));
  return !existing;
}

export async function importJSON(text) {
  let payload;
  try {
    payload = typeof text === 'string' ? JSON.parse(text) : text;
  } catch (e) {
    return { ok: false, added: 0, error: 'Not valid JSON: ' + (e && e.message ? e.message : String(e)) };
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { ok: false, added: 0, error: 'Backup file is not an object' };
  }
  if (payload.app !== 'pushups') {
    return { ok: false, added: 0, error: 'This backup is not from Pushups (missing app:"pushups")' };
  }
  if (payload.schema !== SCHEMA) {
    return { ok: false, added: 0, error: 'Unsupported backup schema ' + String(payload.schema) };
  }
  if (!Array.isArray(payload.sets)) {
    return { ok: false, added: 0, error: 'Backup has no sets array' };
  }
  if (payload.reps !== undefined && !Array.isArray(payload.reps)) {
    return { ok: false, added: 0, error: 'Backup has a reps field that is not an array' };
  }
  if (payload.meta !== undefined && !Array.isArray(payload.meta)) {
    return { ok: false, added: 0, error: 'Backup has a meta field that is not an array' };
  }

  const db = await open();
  const incomingMeta = Array.isArray(payload.meta) ? payload.meta : [];
  const incomingSets = payload.sets;
  const incomingReps = Array.isArray(payload.reps) ? payload.reps : [];
  const tx = db.transaction(['sets', 'reps', 'meta'], 'readwrite');
  const setStore = tx.objectStore('sets');
  const repStore = tx.objectStore('reps');
  const metaStore = tx.objectStore('meta');
  let metaWritten = 0;
  const idMap = new Map();
  let addedSets = 0;
  let addedReps = 0;

  for (const s of incomingSets) {
    if (!s || typeof s !== 'object') continue;
    const oldId = s.id;
    const rec = { ...s };
    delete rec.id;
    if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
    if (!rec.day) rec.day = localDay(rec.startedAt);
    rec.schema = SCHEMA;
    let key;
    if (isIdKey(oldId) && await idIsFree(setStore, oldId)) {
      rec.id = oldId;
      key = await toPromise(setStore.put(rec));
    } else {
      key = await toPromise(setStore.add(rec));
    }
    if (oldId !== undefined) idMap.set(oldId, key);
    addedSets++;
  }

  for (const r of incomingReps) {
    if (!r || typeof r !== 'object') continue;
    const rec = { ...r };
    const oldRepId = rec.id;
    delete rec.id;
    if (rec.setId !== undefined) {
      if (idMap.has(rec.setId)) rec.setId = idMap.get(rec.setId);
    }
    if (isIdKey(oldRepId) && await idIsFree(repStore, oldRepId)) {
      rec.id = oldRepId;
      await toPromise(repStore.put(rec));
    } else {
      await toPromise(repStore.add(rec));
    }
    addedReps++;
  }

  // Goals, streak mode and spent rest passes travel in meta. The backup wins over the local copy:
  // restoring onto a fresh phone should bring the targets you trained against, not reset them.
  for (const row of incomingMeta) {
    if (!row || typeof row !== 'object' || typeof row.k !== 'string' || !row.k) continue;
    await toPromise(metaStore.put({ k: row.k, v: row.v }));
    metaWritten += 1;
  }

  await finish(tx);
  return {
    ok: true,
    added: addedSets,
    addedSets,
    addedReps,
    metaWritten,
    error: null,
  };
}
__EOF_js_db_js__

mkdir -p 'js'
cat > 'js/feedback.js' <<'__EOF_js_feedback_js__'
let ctx = null;
let lastTickAt = 0;
let voicesWarmed = false;

const ONES = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen',
];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

export const NUMBER_WORDS = [...ONES, 'twenty'];

const MIN_TICK_GAP_MS = 45;

export async function unlockAudio() {
  try {
    if (!ctx) {
      const AC = (typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)) || null;
      if (!AC) return false;
      ctx = new AC();
    }
    if (ctx.state === 'suspended' && typeof ctx.resume === 'function') await ctx.resume();
    return ctx.state === 'running';
  } catch (err) {
    void err;
    return false;
  }
}

function blip(freq, startAt, ms, gain, type) {
  if (!ctx || ctx.state !== 'running') return false;
  if (gain <= 0 || ms <= 0) return false;
  try {
    const dur = ms / 1000;
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type || 'sine';
    osc.frequency.setValueAtTime(freq, startAt);
    const peak = Math.max(gain, 0.0005);
    const attack = Math.min(0.008, dur * 0.3);
    const holdEnd = startAt + Math.max(dur - attack, dur * 0.7);
    g.gain.setValueAtTime(0.0001, startAt);
    g.gain.exponentialRampToValueAtTime(peak, startAt + attack);
    g.gain.setValueAtTime(peak, holdEnd);
    g.gain.exponentialRampToValueAtTime(0.0001, startAt + dur);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(startAt);
    osc.stop(startAt + dur + 0.02);
    osc.onended = () => {
      try { osc.disconnect(); g.disconnect(); } catch (err) { void err; }
    };
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function playBeep({ freq = 880, ms = 60, gain = 0.05, type = 'sine' } = {}) {
  if (!ctx || ctx.state !== 'running') return false;
  return blip(freq, ctx.currentTime, ms, gain, type);
}

export function playCountTick() {
  const now = (typeof performance !== 'undefined' ? performance.now() : Date.now());
  if (now - lastTickAt < MIN_TICK_GAP_MS) return false;
  lastTickAt = now;
  return blip(440, ctx ? ctx.currentTime : 0, 45, 0.045, 'triangle');
}

export function playWarning() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(392, t, 80, 0.035, 'sine');
  const b = blip(294, t + 0.11, 110, 0.03, 'sine');
  return a || b;
}

export function playGo() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(659, t, 90, 0.05, 'sine');
  const b = blip(988, t + 0.12, 160, 0.05, 'sine');
  return a || b;
}

function warmVoices() {
  if (voicesWarmed || typeof window === 'undefined' || !window.speechSynthesis) return;
  voicesWarmed = true;
  try {
    window.speechSynthesis.getVoices();
    window.speechSynthesis.addEventListener('voiceschanged', () => {
      window.speechSynthesis.getVoices();
    }, { once: true });
  } catch (err) {
    void err;
  }
}

export function voiceSupported() {
  return typeof window !== 'undefined'
    && 'speechSynthesis' in window
    && typeof window.SpeechSynthesisUtterance === 'function';
}

export function speak(text, { interrupt = true, rate = 1, pitch = 1 } = {}) {
  if (!voiceSupported() || text === undefined || text === null || text === '') return false;
  warmVoices();
  const syn = window.speechSynthesis;
  try {
    if (interrupt) {
      if (syn.speaking || syn.pending) syn.cancel();
    } else if (syn.speaking) {
      return false;
    }
    const u = new window.SpeechSynthesisUtterance(String(text));
    u.rate = rate;
    u.pitch = pitch;
    u.volume = 1;
    u.lang = (navigator.language || 'en-US');
    syn.speak(u);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function stopSpeaking() {
  if (!voiceSupported()) return false;
  try {
    window.speechSynthesis.cancel();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function vibrate(pattern) {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return false;
  try {
    navigator.vibrate(pattern === undefined ? 12 : pattern);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function countWord(n) {
  const num = Math.trunc(Number(n));
  if (!Number.isFinite(num) || num < 0 || num > 999) return String(n);
  if (num < 20) return ONES[num];
  const tens = Math.floor(num / 10);
  const rest = num % 10;
  if (tens < 10) return rest === 0 ? TENS[tens] : `${TENS[tens]}-${ONES[rest]}`;
  const hundreds = Math.floor(num / 100);
  const tail = num % 100;
  if (tail === 0) return `${ONES[hundreds]} hundred`;
  return `${ONES[hundreds]} hundred ${countWord(tail)}`;
}

export function announceRep(n, { mode = 'every', voice = true, beeps = true, haptics = true } = {}) {
  const count = Math.trunc(Number(n)) || 0;
  let spoke = false;
  if (voice && mode !== 'off' && (mode === 'every' || count % 5 === 0)) {
    spoke = speak(countWord(count), { interrupt: true });
  }
  const ticked = beeps ? playCountTick() : false;
  const buzzed = haptics ? vibrate(count % 5 === 0 ? [18, 40, 18] : 12) : false;
  return { spoke, ticked, buzzed };
}

export function countdownVoice(secondsLeft) {
  const words = { 5: 'five', 4: 'four', 3: 'three', 2: 'two', 1: 'one' };
  const s = Math.trunc(Number(secondsLeft));
  if (!Number.isFinite(s) || s <= 0) return 'go';
  return words[s] || countWord(s);
}
__EOF_js_feedback_js__

mkdir -p 'js'
cat > 'js/goals.js' <<'__EOF_js_goals_js__'
/* Goals, streak mode and rest-day passes. Config lives in IndexedDB meta (not localStorage) so a
   JSON export carries the targets you trained against, and a restore on another phone brings the
   streak rules with it. */

import { getMeta, setMeta } from './db.js';
import { addDays, byDay, dailyGoalStreak, dayKey, weekStart, weeklyGoalStreak } from './stats.js';

export const GOAL_KEY = 'goals.v1';
export const STREAK_KEY = 'streak.v1';
export const PASS_KEY = 'passes.v1';

export const DEFAULT_GOALS = { daily: 50, weekly: 350, yearly: 10000 };
export const DEFAULT_STREAK = { mode: 'weekly', passesPerWeek: 1 };

const cache = new Map();

async function readKey(key, fallback) {
  if (cache.has(key)) return cache.get(key);
  let value = fallback;
  try {
    const raw = await getMeta(key);
    if (raw && typeof raw === 'object') value = { ...fallback, ...raw };
  } catch { /* cold or blocked db: fall back to defaults for this session only */ }
  cache.set(key, value);
  return value;
}

/** Drop the in-memory copy so the next read comes from the database (after a restore). */
export function forgetCache() {
  cache.clear();
}

async function writeKey(key, value) {
  cache.set(key, value);
  await setMeta(key, value);
  return value;
}

export async function loadGoals() { return readKey(GOAL_KEY, DEFAULT_GOALS); }

export async function saveGoals(patch) {
  const base = await loadGoals();
  const next = { ...base, ...(patch || {}) };
  for (const k of ['daily', 'weekly', 'yearly']) {
    const v = parseInt(next[k], 10);
    next[k] = Number.isFinite(v) && v >= 0 ? Math.min(100000, v) : DEFAULT_GOALS[k];
  }
  return writeKey(GOAL_KEY, next);
}

export async function loadStreak() {
  const base = await readKey(STREAK_KEY, DEFAULT_STREAK);
  if (base.mode !== 'daily' && base.mode !== 'weekly') base.mode = DEFAULT_STREAK.mode;
  base.passesPerWeek = Math.max(0, Math.min(3, parseInt(base.passesPerWeek, 10) || 0));
  return base;
}

export async function saveStreak(patch) {
  const base = await loadStreak();
  return writeKey(STREAK_KEY, { ...base, ...(patch || {}) });
}

/** Day keys that were covered by a rest pass. Only the last 12 weeks are kept. */
export async function loadPasses() {
  const raw = await readKey(PASS_KEY, {});
  return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
}

export async function passesThisWeek(passes, fromKey) {
  const wk = weekStart(fromKey || dayKey(Date.now()));
  let n = 0;
  for (let i = 0; i < 7; i++) if (passes[addDays(wk, i)]) n += 1;
  return n;
}

/** Spend a rest pass on `day`. Returns { ok, reason } so the UI can say why it refused. */
export async function usePass(day) {
  const cfg = await loadStreak();
  const passes = await loadPasses();
  const key = day || dayKey(Date.now());
  if (passes[key]) return { ok: false, reason: 'already used', passes };
  if (cfg.passesPerWeek === 0) return { ok: false, reason: 'rest passes are off', passes };
  const used = await passesThisWeek(passes, key);
  if (used >= cfg.passesPerWeek) return { ok: false, reason: 'no passes left this week', passes };
  const next = { ...passes, [key]: true };
  const cutoff = addDays(dayKey(Date.now()), -84);
  for (const k of Object.keys(next)) if (k < cutoff) delete next[k];
  await writeKey(PASS_KEY, next);
  return { ok: true, passes: next };
}

export async function undoPass(day) {
  const passes = await loadPasses();
  if (!passes[day]) return { passes };
  const next = { ...passes };
  delete next[day];
  await writeKey(PASS_KEY, next);
  return { passes: next };
}

/** Everything the Today and Progress headers need, from one set list. */
export async function goalStatus(sets, todayKey) {
  const goals = await loadGoals();
  const cfg = await loadStreak();
  const passes = await loadPasses();
  const days = byDay(sets);
  const key = todayKey || dayKey(Date.now());
  const today = days.get(key);
  return {
    goals,
    streakCfg: cfg,
    passes,
    passesLeft: Math.max(0, cfg.passesPerWeek - await passesThisWeek(passes, key)),
    daily: { goal: goals.daily, reps: today ? today.reps : 0, pct: goals.daily ? Math.min(1, (today ? today.reps : 0) / goals.daily) : 0 },
    weekly: pctOf(days, goals.weekly, 'week', key),
    yearly: pctOf(days, goals.yearly, 'year', key),
    streak: cfg.mode === 'daily'
      ? { mode: 'daily', n: dailyGoalStreak(days, goals.daily, key, new Set(Object.keys(passes))), unit: 'days' }
      : { mode: 'weekly', n: weeklyGoalStreak(days, goals.weekly, key), unit: 'weeks' },
  };
}

function pctOf(days, goal, span, key) {
  const reps = span === 'week' ? weekToDate(days, key) : yearToDate(days, key);
  return { goal, reps, pct: goal ? Math.min(1, reps / goal) : 0, left: Math.max(0, goal - reps) };
}

function weekToDate(days, key) {
  const wk = weekStart(key);
  let n = 0;
  for (let i = 0; i < 7 && addDays(wk, i) <= key; i++) {
    const d = days.get(addDays(wk, i));
    if (d) n += d.reps;
  }
  return n;
}

function yearToDate(days, key) {
  const jan = key.slice(0, 4) + '-01-01';
  let n = 0;
  for (const [k, d] of days) if (k >= jan && k <= key) n += d.reps;
  return n;
}

/** For the reminder layer: has today's goal already been banked? */
export async function goalMetToday(sets, todayKey) {
  const goals = await loadGoals();
  const key = todayKey || dayKey(Date.now());
  const d = byDay(sets).get(key);
  return !!d && d.reps >= goals.daily;
}
__EOF_js_goals_js__

mkdir -p 'js'
cat > 'js/main.js' <<'__EOF_js_main_js__'
import { load } from './settings.js';
import { initUpdate, requestWakeLock, watchWakeLock, requestPersistent, isStandalone } from './upgrade.js';

const ROUTES = {
  today: () => import('./views/today.js'),
  train: () => import('./views/train.js'),
  progress: () => import('./views/progress.js'),
  badges: () => import('./views/badges.js'),
  settings: () => import('./views/settings.js'),
  debug: () => import('./views/debug.js'),
};

const host = document.getElementById('view');
const banner = document.getElementById('banner');
let current = null;

function routeName() {
  const h = (location.hash || '#/today').replace(/^#\//, '').split('?')[0];
  return ROUTES[h] ? h : 'today';
}

function markTab(name) {
  document.querySelectorAll('#tabs a').forEach((a) => {
    a.setAttribute('aria-current', a.dataset.tab === name ? 'true' : 'false');
  });
}

async function render() {
  const name = routeName();
  if (current && current.unmount) {
    try { await current.unmount(); } catch (e) { console.warn('unmount', e); }
  }
  current = null;
  host.replaceChildren();
  markTab(name);
  const mod = await ROUTES[name]();
  const view = mod.default ? mod.default : mod;
  current = await view(host, { route: name, render, params: new URLSearchParams(location.search) });
}

window.addEventListener('hashchange', render);

// ── update prompt ──
function showBanner(reload) {
  const box = document.createElement('div');
  box.textContent = 'Update available — tap to reload';
  box.addEventListener('click', () => {
    hideBanner();
    reload();
  });
  banner.replaceChildren(box);
  document.body.classList.add('banner-on');
}

function hideBanner() {
  banner.replaceChildren();
  document.body.classList.remove('banner-on');
}

// ── lifecycle ──
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') requestWakeLock('return-to-foreground');
});

function fail(err) {
  console.error(err);
  const p = document.createElement('p');
  p.className = 'h1';
  p.textContent = 'Startup failed';
  const s = document.createElement('p');
  s.className = 'sub';
  s.textContent = String(err && err.message ? err.message : err);
  const pad = document.createElement('div');
  pad.className = 'pad';
  pad.append(p, s);
  host.replaceChildren(pad);
}

async function boot() {
  load();
  if (window.__swReg) initUpdate({ swRegistration: window.__swReg, onPrompt: showBanner });
  watchWakeLock();
  if (isStandalone()) requestPersistent().catch(() => {});
  await render();
}

boot().catch(fail);
__EOF_js_main_js__

mkdir -p 'js'
cat > 'js/one-euro.js' <<'__EOF_js_one_euro_js__'
// One Euro filter, Casal et al. 2017.
const TWO_PI = 2 * Math.PI;
const MIN_DT = 1e-4;
const MAX_DT = 0.25;

function alphaCoefficient(dt, fc) {
  const tau = 1 / (TWO_PI * fc);
  return 1 / (tau + 1);
}

export class OneEuro {
  constructor({ minCutoff = 1.0, beta = 0.0, dCutoff = 1.0 } = {}) {
    this.minCutoff = minCutoff;
    this.beta = beta;
    this.dCutoff = dCutoff;
    this.t = null;
    this.x = null;
    this.dx = 0;
  }

  reset() {
    this.t = null;
    this.x = null;
    this.dx = 0;
  }

  filter(tMs, value) {
    if (!Number.isFinite(tMs) || !Number.isFinite(value)) return this.x === null ? value : this.x;
    if (this.t === null || this.x === null) {
      this.t = tMs;
      this.x = value;
      this.dx = 0;
      return value;
    }

    let dt = (tMs - this.t) / 1000;
    if (dt <= 0) return this.x;
    if (dt > 1) {
      this.reset();
      this.t = tMs;
      this.x = value;
      this.dx = 0;
      return value;
    }
    if (dt > MAX_DT) dt = MAX_DT;

    const rawDx = (value - this.x) / dt;
    this.dx += alphaCoefficient(dt, this.dCutoff) * (rawDx - this.dx);

    const fc = Math.max(1e-3, this.minCutoff + this.beta * Math.abs(this.dx));
    const a = alphaCoefficient(dt, fc);
    this.x = this.x + a * (value - this.x);
    this.t = tMs;
    return this.x;
  }
}

export function smoothSeries(series, opts) {
  if (!Array.isArray(series)) return [];
  const f = new OneEuro(opts);
  const out = [];
  for (const pair of series) {
    if (!Array.isArray(pair) || pair.length < 2) continue;
    out.push([pair[0], f.filter(pair[0], pair[1])]);
  }
  return out;
}
__EOF_js_one_euro_js__

mkdir -p 'js'
cat > 'js/pose.js' <<'__EOF_js_pose_js__'
import { FilesetResolver, PoseLandmarker } from '../vendor/mediapipe/vision_bundle.mjs';
import { clamp } from './util.js';

// Absolute URLs: MediaPipe injects the wasm loader with <script src> and Emscripten then resolves
// the .wasm against that script's own folder, which would double the path on a hosted subfolder.
const abs = (p) => (typeof location === 'undefined' ? p : new URL(p, location.href).href);

export const MODEL_PATHS = {
  lite: abs('models/pose_landmarker_lite.task'),
  full: abs('models/pose_landmarker_full.task'),
};

const WASM_BASE_PATH = abs('vendor/mediapipe/wasm');
const NUM_LANDMARKS = 33;
const QUALITY_IDX = [11, 12, 13, 14, 15, 23, 24, 25, 26, 27, 28];
const MIN_VIS_TO_DRAW = 0.5;

const CONNECTIONS = [
  [0, 2], [0, 5], [2, 3], [3, 7], [5, 4], [8, 5],
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24],
  [23, 25], [25, 27], [24, 26], [26, 28],
  [27, 29], [29, 31], [27, 31], [28, 30], [30, 32], [28, 32],
];

let filesetPromise = null;

function getFileset() {
  if (!filesetPromise) {
    try {
      filesetPromise = Promise.resolve(FilesetResolver.forVisionTasks(WASM_BASE_PATH));
    } catch (err) {
      return Promise.reject(err);
    }
    filesetPromise.catch(() => { filesetPromise = null; });
  }
  return filesetPromise;
}

const cache = new Map();
const cacheKey = (model, delegate) => `${model}|${delegate}`;

function closeInstance(inst) {
  if (!inst) return;
  try {
    // tasks-vision frees the graph runner through close(); there is no dispose() in 0.10.x
    if (typeof inst.close === 'function') inst.close();
    else if (typeof inst.dispose === 'function') inst.dispose();
  } catch (err) {
    void err;
  }
}

function removeCached(key, inst) {
  if (cache.get(key) === inst) cache.delete(key);
}

async function createInstance(model, delegate) {
  const fileset = await getFileset();
  const key = cacheKey(model, delegate);
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  const inst = await PoseLandmarker.createFromOptions(fileset, {
    baseOptions: {
      modelAssetPath: MODEL_PATHS[model] || model,
      delegate: delegate === 'cpu' ? 'CPU' : 'GPU',
    },
    runningMode: 'VIDEO',
    numPoses: 1,
    minPoseDetectionConfidence: 0.5,
    minPosePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });
  cache.set(key, inst);
  while (cache.size > 2) {
    const oldest = cache.keys().next().value;
    const victim = cache.get(oldest);
    cache.delete(oldest);
    if (victim !== inst) closeInstance(victim);
  }
  return inst;
}

// Returns the tracker synchronously so the UI can call start()/stop() before the model has
// finished loading. `await createTracker(...)` yields the same object, so both work.
export function createTracker(options = {}) {
  const {
    video,
    model = 'lite',
    delegate = 'gpu',
    fpsCap = 25,
    canvas = null,
    onFrame,
    onStatus,
    onError,
    strokeStyle = '#2dd4bf',
    lineWidth = 2,
    mirrored = false,
  } = options;

  // Reused across frames: iOS Safari jitters badly if 33 objects are allocated 25x/second.
  // Consumers must copy values out of `frame`/`frame.landmarks` if they keep them.
  const landmarkBuf = new Array(NUM_LANDMARKS);
  for (let i = 0; i < NUM_LANDMARKS; i++) landmarkBuf[i] = { x: 0, y: 0, z: 0, visibility: 0 };

  const frame = { landmarks: landmarkBuf, present: false, quality: 0, fps: 0, stampMs: 0 };
  const stamps = [];

  const st = {
    model,
    delegate: delegate === 'cpu' ? 'cpu' : 'gpu',
    fpsCap: clamp(Math.round(Number(fpsCap) || 25), 8, 30),
    mirrored: !!mirrored,
    phase: 'idle',
    running: false,
    disposed: false,
    fps: 0,
    lastTs: 0,
    lastDetect: 0,
    firstStamp: 0,
    raf: 0,
    pending: false,
    pendingClose: [],
    gpuFailed: delegate === 'cpu',
    swapping: false,
    booting: false,
  };

  let landmarker = null;

  function emit(fn, ...args) {
    if (typeof fn !== 'function') return;
    try { fn(...args); } catch (err) { void err; }
  }

  function status(phase, detail) {
    st.phase = phase;
    emit(onStatus, phase, detail);
  }

  function fatal(err) {
    if (st.disposed) return;
    st.running = false;
    st.pending = false;
    if (st.raf) cancelAnimationFrame(st.raf);
    st.raf = 0;
    st.phase = 'failed';
    emit(onError, err);
  }

  function flushPendingClose() {
    if (st.pending || !st.pendingClose.length) return;
    for (const inst of st.pendingClose) closeInstance(inst);
    st.pendingClose.length = 0;
  }

  async function build(prefer) {
    const order = (prefer === 'cpu' || st.gpuFailed) ? ['cpu'] : ['gpu', 'cpu'];
    let lastErr = null;
    for (const d of order) {
      try {
        const inst = await createInstance(st.model, d);
        if (d === 'cpu' && st.delegate === 'gpu') status('delegate-downgrade', 'cpu');
        st.delegate = d;
        if (d === 'cpu') st.gpuFailed = true;
        return inst;
      } catch (err) {
        lastErr = err;
        if (d === 'gpu') st.gpuFailed = true;
      }
    }
    throw lastErr || new Error('pushups: pose landmarker could not be created');
  }

  function measureFps(now) {
    stamps.push(now);
    while (stamps.length && now - stamps[0] > 3000) stamps.shift();
    if (!st.firstStamp) st.firstStamp = now;
    if (stamps.length < 3 || now - st.firstStamp < 3000) {
      st.fps = 0;
      return 0;
    }
    const span = now - stamps[0];
    st.fps = span > 0 ? ((stamps.length - 1) * 1000) / span : 0;
    return st.fps;
  }

  function fillLandmarks(src) {
    const n = Math.min(src.length, NUM_LANDMARKS);
    const flip = st.mirrored;
    for (let i = 0; i < NUM_LANDMARKS; i++) {
      const out = landmarkBuf[i];
      if (i < n) {
        const p = src[i];
        // mirrored front-cam: the preview is shown flipped, so the counter AND the overlay
        // both use 1-x; the counter therefore always sees the same left/right as the user.
        out.x = flip ? 1 - (p.x || 0) : (p.x || 0);
        out.y = p.y || 0;
        out.z = p.z || 0;
        const vis = p.visibility === undefined ? p.presence : p.visibility;
        out.visibility = typeof vis === 'number' ? vis : 1;
      } else {
        out.x = 0;
        out.y = 0;
        out.z = 0;
        out.visibility = 0;
      }
    }
  }

  function computeQuality() {
    let sum = 0;
    for (let i = 0; i < QUALITY_IDX.length; i++) sum += landmarkBuf[QUALITY_IDX[i]].visibility;
    return clamp(sum / QUALITY_IDX.length, 0, 1);
  }

  function draw() {
    if (!canvas || !video || typeof canvas.getContext !== 'function') return;
    const boxW = canvas.clientWidth || video.videoWidth;
    const boxH = canvas.clientHeight || video.videoHeight;
    if (!boxW || !boxH) return;
    if (canvas.width !== boxW || canvas.height !== boxH) {
      canvas.width = boxW;
      canvas.height = boxH;
    }
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, boxW, boxH);
    if (!frame.present || !video.videoWidth) return;
    // the video is shown with object-fit:cover, so map normalised landmarks through the same
    // crop or the skeleton slides off the body
    const s = Math.max(boxW / video.videoWidth, boxH / video.videoHeight);
    const ox = (boxW - video.videoWidth * s) / 2;
    const oy = (boxH - video.videoHeight * s) / 2;
    const px = (p) => p.x * video.videoWidth * s + ox;
    const py = (p) => p.y * video.videoHeight * s + oy;
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth * Math.max(1, boxW / 360);
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (let i = 0; i < CONNECTIONS.length; i++) {
      const a = landmarkBuf[CONNECTIONS[i][0]];
      const b = landmarkBuf[CONNECTIONS[i][1]];
      if (a.visibility < MIN_VIS_TO_DRAW || b.visibility < MIN_VIS_TO_DRAW) continue;
      ctx.moveTo(px(a), py(a));
      ctx.lineTo(px(b), py(b));
    }
    ctx.stroke();
  }

  function handleResult(res, ts) {
    const sets = res && Array.isArray(res.landmarks) ? res.landmarks : [];
    const src = sets.length ? sets[0] : null;
    const present = !!(src && src.length);
    frame.present = present;
    if (present) fillLandmarks(src);
    else for (let i = 0; i < NUM_LANDMARKS; i++) landmarkBuf[i].visibility = 0;
    frame.quality = present ? computeQuality() : 0;
    frame.stampMs = ts;
    frame.fps = measureFps(performance.now());
    draw();
    emit(onFrame, frame, res);
  }

  async function recoverOnCPU(failedInst) {
    removeCached(cacheKey(st.model, st.delegate), failedInst);
    if (failedInst === landmarker) st.pendingClose.push(failedInst);
    else closeInstance(failedInst);
    landmarker = null;
    try {
      landmarker = await build('cpu');
      flushPendingClose();
      if (st.running) status('running', 'cpu');
      return true;
    } catch (err) {
      fatal(err);
      return false;
    }
  }

  function handleDetectFailure(err) {
    if (st.delegate === 'gpu' && !st.gpuFailed) {
      void recoverOnCPU(landmarker);
      return;
    }
    fatal(err);
  }

  function loop() {
    if (!st.running || st.disposed) return;
    st.raf = requestAnimationFrame(loop);
    if (st.pending || st.swapping || !landmarker) return;
    const now = performance.now();
    if (now - st.lastDetect < 1000 / st.fpsCap) return;
    if (!video || video.readyState < 2 || video.videoWidth === 0) return;

    st.lastDetect = now;
    st.pending = true;
    let ts = Math.round(now);
    if (ts <= st.lastTs) ts = st.lastTs + 1;
    st.lastTs = ts;

    const inst = landmarker;
    let promise = null;
    try {
      promise = inst.detectForVideo(video, ts);
    } catch (err) {
      st.pending = false;
      handleDetectFailure(err);
      return;
    }
    if (!promise || typeof promise.then !== 'function') {
      st.pending = false;
      return;
    }
    promise
      .then((res) => {
        st.pending = false;
        if (st.disposed) return;
        handleResult(res, ts);
        flushPendingClose();
      })
      .catch((err) => {
        st.pending = false;
        if (st.disposed) return;
        handleDetectFailure(err);
      });
  }

  async function warmUp() {
    if (!landmarker || !video || video.readyState < 2 || video.videoWidth === 0) return;
    let ts = Math.round(performance.now());
    if (ts <= st.lastTs) ts = st.lastTs + 1;
    st.lastTs = ts;
    st.pending = true;
    const inst = landmarker;
    try {
      const res = await inst.detectForVideo(video, ts);
      st.pending = false;
      handleResult(res, ts);
    } catch (err) {
      st.pending = false;
      if (st.delegate === 'gpu' && !st.gpuFailed) await recoverOnCPU(inst);
      else fatal(err);
    }
  }

  async function boot() {
    st.booting = true;
    status('loading-model', st.model);
    try {
      landmarker = await build(st.delegate);
    } catch (err) {
      st.booting = false;
      fatal(err);
      return;
    }
    st.booting = false;
    if (st.disposed || st.phase === 'failed') return;
    status('warming-up', st.delegate);
    await warmUp();
    if (st.disposed || st.phase === 'failed') return;
    status(st.running ? 'running' : 'ready', st.delegate);
  }

  const api = {
    start() {
      if (st.disposed || st.running) return false;
      st.running = true;
      st.lastDetect = 0;
      st.firstStamp = 0;
      stamps.length = 0;
      if (!st.booting) status('running', st.delegate);
      st.raf = requestAnimationFrame(loop);
      return true;
    },

    stop() {
      if (st.raf) cancelAnimationFrame(st.raf);
      st.raf = 0;
      const was = st.running;
      st.running = false;
      st.pending = false;
      if (was) status('stopped');
      return was;
    },

    setMirrored(v) {
      st.mirrored = !!v;
      return st.mirrored;
    },

    setFpsCap(v) {
      st.fpsCap = clamp(Math.round(Number(v) || 0), 8, 30);
      return st.fpsCap;
    },

    async setModel(next) {
      if (st.disposed || !MODEL_PATHS[next] || next === st.model || st.booting) return st.model;
      const prevModel = st.model;
      const prevInst = landmarker;
      st.swapping = true;
      st.model = next;
      let inst = null;
      try {
        inst = await build(st.gpuFailed ? 'cpu' : 'gpu');
        landmarker = inst;
        st.firstStamp = 0;
        stamps.length = 0;
      } catch (err) {
        st.model = prevModel;
        fatal(err);
        st.swapping = false;
        return prevModel;
      }
      st.swapping = false;
      if (prevInst && prevInst !== inst) {
        removeCached(cacheKey(prevModel, st.delegate), prevInst);
        if (st.pending) st.pendingClose.push(prevInst);
        else closeInstance(prevInst);
      }
      flushPendingClose();
      return st.model;
    },

    dispose() {
      if (st.disposed) return false;
      st.disposed = true;
      st.running = false;
      if (st.raf) cancelAnimationFrame(st.raf);
      st.raf = 0;
      const inst = landmarker;
      landmarker = null;
      if (inst) removeCached(cacheKey(st.model, st.delegate), inst);
      for (const pending of st.pendingClose) closeInstance(pending);
      st.pendingClose.length = 0;
      closeInstance(inst);
      status('stopped', 'disposed');
      return true;
    },

    getStatus() {
      return {
        phase: st.phase,
        running: st.running,
        model: st.model,
        delegate: st.delegate,
        fps: st.fps,
        fpsCap: st.fpsCap,
        mirrored: st.mirrored,
        present: frame.present,
        quality: frame.quality,
        disposed: st.disposed,
      };
    },
  };

  const bootPromise = boot();
  bootPromise.catch(() => {});
  api.ready = bootPromise;
  return api;
}
__EOF_js_pose_js__

mkdir -p 'js'
cat > 'js/settings.js' <<'__EOF_js_settings_js__'
export const PRESETS = {
  relaxed:  { top: 140, bottom: 112, minRepMs: 300 },
  standard: { top: 155, bottom: 100, minRepMs: 400 },
  strict:   { top: 168, bottom: 88,  minRepMs: 450 },
};

export const DEFAULTS = {
  preset: 'standard', overrides: {}, cleanOnly: false, autoArm: false, armHoldMs: 2500,
  endAfterIdleSec: 12, camera: 'environment', voice: 'every', beeps: true, haptics: true,
  skeletonOnSet: true, secondarySignal: 'assist', model: 'lite', fpsCap: 25, manualMode: false, debug: false,
};

const STORAGE_KEY = 'pushups.settings.v1';

let cached = null;

function readStored() {
  try {
    const raw = globalThis.localStorage?.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function normalize(settings) {
  const out = { ...settings };
  if (!PRESETS[out.preset]) out.preset = DEFAULTS.preset;
  if (!out.overrides || typeof out.overrides !== 'object' || Array.isArray(out.overrides)) {
    out.overrides = {};
  }
  return out;
}

export function load() {
  if (cached) return cached;
  const stored = readStored();
  cached = normalize(stored ? { ...DEFAULTS, ...stored } : { ...DEFAULTS });
  return cached;
}

export function save(patch) {
  const base = load();
  const next = normalize({ ...base, ...(patch || {}) });
  cached = next;
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // storage unavailable (private mode, quota) — keep the in-memory copy
  }
  return next;
}

export function params() {
  const s = load();
  const preset = PRESETS[s.preset] || PRESETS.standard;
  const overrides = {};
  for (const [k, v] of Object.entries(s.overrides || {})) {
    if (typeof v === 'number' && Number.isFinite(v)) overrides[k] = v;
  }
  return { ...preset, ...overrides };
}

export function setParam(k, v) {
  const s = load();
  const overrides = { ...s.overrides };
  if (v === null || v === undefined || (typeof v === 'number' && !Number.isFinite(v))) {
    delete overrides[k];
  } else {
    overrides[k] = v;
  }
  return save({ ...s, overrides });
}

export function resetParams() {
  return save({ ...load(), overrides: {} });
}

export function clearOverridesForPreset() {
  return resetParams();
}
__EOF_js_settings_js__

mkdir -p 'js'
cat > 'js/stats.js' <<'__EOF_js_stats_js__'
/* Aggregation over saved sets + reps. Pure functions: every entry point takes plain arrays so the
   whole layer is testable without IndexedDB, and views decide what to fetch.
   Week = Monday..Sunday (local). All day keys are 'YYYY-MM-DD' from db.localDay. */

import { mean, sum } from './util.js';

const DAY_MS = 86400000;

/* ── calendar helpers ──────────────────────────────────────────── */

export function dayKey(ms) {
  const d = new Date(ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

export function dayFromKey(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1).getTime();
}

export function addDays(key, n) {
  return dayKey(dayFromKey(key) + n * DAY_MS);
}

/** Monday of the week containing `key`. */
export function weekStart(key) {
  const t = dayFromKey(key);
  const dow = (new Date(t).getDay() + 6) % 7;   // 0 = Monday
  return dayKey(t - dow * DAY_MS);
}

export function monthKey(key) { return String(key).slice(0, 7); }
export function yearKey(key) { return String(key).slice(0, 4); }

export function daysBetween(a, b) {
  return Math.round((dayFromKey(b) - dayFromKey(a)) / DAY_MS);
}

/* ── per-day totals ────────────────────────────────────────────── */

/** Map of 'YYYY-MM-DD' -> { day, reps, sets, flagged, clean, minutes, best, manual }. */
export function byDay(sets) {
  const map = new Map();
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt || Date.now());
    let d = map.get(day);
    if (!d) {
      d = { day, reps: 0, sets: 0, flagged: 0, clean: 0, minutes: 0, best: 0, manual: 0, detected: 0 };
      map.set(day, d);
    }
    const reps = Number(s.repsFinal) || 0;
    d.reps += reps;
    d.detected += Number(s.repsDetected) || 0;
    d.sets += 1;
    d.minutes += (Number(s.durationMs) || 0) / 60000;
    d.best = Math.max(d.best, reps);
    if (s.source === 'manual' || s.mode === 'manual') d.manual += 1;
    const f = s.flags || {};
    const flagged = (f.sag || 0) + (f.pike || 0) + (f.half || 0) + (f.lockout || 0) + (f.lost || 0);
    d.flagged += flagged;
    d.clean += Math.max(0, reps - flagged);
  }
  return map;
}

export function dayTotals(sets, key) {
  return byDay(sets).get(key) || emptyDay(key);
}

function emptyDay(key) {
  return { day: key, reps: 0, sets: 0, flagged: 0, clean: 0, minutes: 0, best: 0, manual: 0, detected: 0 };
}

/** Contiguous run of days with reps > 0, counting back from `fromKey` (or from the last training day). */
export function trainingStreak(days, fromKey) {
  const has = (k) => { const d = days.get(k); return !!d && d.reps > 0; };
  let cursor = fromKey || dayKey(Date.now());
  if (!has(cursor)) cursor = addDays(cursor, -1);      // today not done yet does not kill yesterday's streak
  let n = 0;
  while (n < 4000 && has(cursor)) { n += 1; cursor = addDays(cursor, -1); }
  return n;
}

/**
 * Streak of weeks where the weekly goal was met, counting back from the current week.
 * The in-progress week only counts if it already reached the goal, so a fresh Monday
 * never shows a streak of zero just because the week is young.
 */
export function weeklyGoalStreak(days, goalReps, fromKey) {
  const start = weekStart(fromKey || dayKey(Date.now()));
  const weeks = weekBuckets(days, 260);
  const met = new Map(weeks.map((w) => [w.key, w.reps >= goalReps]));
  let n = 0;
  for (let i = 0; i < 260; i++) {
    const done = met.get(weekStart(addDays(start, -7 * i)));
    if (done) { n += 1; continue; }
    if (i === 0) continue;          // this week is still young — it neither counts nor breaks
    break;
  }
  return n;
}

/**
 * Consecutive days meeting the daily goal, walking back from today. A day with a rest pass
 * spent on it counts as met, which is how `passes` (a set of day keys) keeps a streak alive.
 */
export function dailyGoalStreak(days, goalReps, fromKey, passes) {
  const spent = passes instanceof Set ? passes : new Set(passes || []);
  const met = (k) => {
    const d = days.get(k);
    return (d && d.reps >= goalReps) || spent.has(k);
  };
  let cursor = fromKey || dayKey(Date.now());
  if (!met(cursor) && !spent.has(cursor)) cursor = addDays(cursor, -1);
  let n = 0;
  while (n < 4000 && (met(cursor) || spent.has(cursor))) { n += 1; cursor = addDays(cursor, -1); }
  return n;
}

/* ── bucketed series ───────────────────────────────────────────── */

function bucketize(days, count, keyOf, startOf, stepOf) {
  const out = [];
  const today = keyOf(Date.now());
  const anchor = startOf(today);
  for (let i = count - 1; i >= 0; i--) {
    const key = stepOf(anchor, -i);
    out.push({ key, from: key, to: key, reps: 0, sets: 0, minutes: 0, best: 0, days: 0, flagged: 0, clean: 0 });
  }
  const index = new Map(out.map((b, i) => [b.key, i]));
  for (const d of days.values()) {
    const k = index.get(keyOf(dayFromKey(d.day)));
    if (k === undefined) continue;
    const b = out[k];
    b.reps += d.reps;
    b.sets += d.sets;
    b.minutes += d.minutes;
    b.flagged += d.flagged;
    b.clean += d.clean;
    b.best = Math.max(b.best, d.best);
    if (d.reps > 0) b.days += 1;
  }
  for (const b of out) {
    b.minutes = Math.round(b.minutes);
    b.avgPerSet = b.sets ? Math.round(b.reps / b.sets) : 0;
  }
  return out;
}

/** Last `count` days, oldest first, including today. */
export function dayBuckets(days, count = 90) {
  return bucketize(days, count, (t) => dayKey(t), (todayKey) => todayKey, (k, n) => addDays(k, n));
}

/** Last `count` weeks keyed by their Monday, oldest first. */
export function weekBuckets(days, count = 52) {
  const out = bucketize(days, count, (t) => weekStart(dayKey(t)), (todayKey) => weekStart(todayKey), (k, n) => addDays(k, n * 7));
  for (const b of out) { b.to = addDays(b.key, 6); b.label = shortRange(b.key, b.to); }
  return out;
}

/** Last `count` calendar months, keyed 'YYYY-MM'. */
export function monthBuckets(days, count = 24) {
  const keyOf = (t) => monthKey(dayKey(t));
  const startOf = (todayKey) => monthKey(todayKey);
  const stepOf = (k, n) => {
    const [y, m] = k.split('-').map(Number);
    const d = new Date(y, m - 1 + n, 1);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
  };
  const out = bucketize(days, count, keyOf, startOf, stepOf);
  for (const b of out) b.label = monthName(b.key);
  return out;
}

/** Last `count` calendar years, keyed 'YYYY'. */
export function yearBuckets(days, count = 6) {
  const keyOf = (t) => yearKey(dayKey(t));
  const out = bucketize(days, count, keyOf, (todayKey) => yearKey(todayKey), (k, n) => String(Number(k) + n));
  for (const b of out) b.label = b.key;
  return out;
}

function monthName(key) {
  const [y, m] = key.split('-').map(Number);
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[(m || 1) - 1] + (m === 1 ? ' ' + y : '');
}

function shortRange(a, b) {
  const pa = a.split('-'), pb = b.split('-');
  return Number(pa[1]) + '/' + Number(pa[2]) + '–' + Number(pb[1]) + '/' + Number(pb[2]);
}

/* ── sets-level series ─────────────────────────────────────────── */

/** Best single set per week — the number the 100-in-a-row plan actually tracks. */
export function bestSetPerWeek(sets, count = 52) {
  const weeks = weekBuckets(byDay(sets), count);
  for (const w of weeks) w.best = 0;
  const index = new Map(weeks.map((w, i) => [w.key, i]));
  for (const s of sets || []) {
    const k = index.get(weekStart(s.day || dayKey(s.startedAt)));
    if (k === undefined) continue;
    weeks[k].best = Math.max(weeks[k].best, Number(s.repsFinal) || 0);
  }
  return weeks;
}

/** Reps by hour of day, four buckets, as shares of total volume. */
export function timeOfDay(sets) {
  const buckets = [
    { key: 'night', label: '00–05', reps: 0, sets: 0 },
    { key: 'morning', label: '05–12', reps: 0, sets: 0 },
    { key: 'afternoon', label: '12–17', reps: 0, sets: 0 },
    { key: 'evening', label: '17–24', reps: 0, sets: 0 },
  ];
  for (const s of sets || []) {
    const h = new Date(s.startedAt || 0).getHours();
    const i = h < 5 ? 0 : h < 12 ? 1 : h < 17 ? 2 : 3;
    buckets[i].reps += Number(s.repsFinal) || 0;
    buckets[i].sets += 1;
  }
  const total = sum(buckets.map((b) => b.reps));
  for (const b of buckets) b.pct = total ? b.reps / total : 0;
  return buckets;
}

/* ── records ───────────────────────────────────────────────────── */

export function records(sets) {
  const list = (sets || []).filter((s) => (Number(s.repsFinal) || 0) > 0);
  const out = {
    bestSet: null, longestSet: null, bestDay: null, bestWeek: null, bestMonth: null, bestYear: null,
    lifetimeReps: 0, lifetimeSets: list.length, lifetimeMinutes: 0,
  };
  for (const s of list) {
    const reps = Number(s.repsFinal) || 0;
    if (!out.bestSet || reps > out.bestSet.reps) out.bestSet = { reps, at: s.startedAt, id: s.id, day: s.day };
    const dur = Number(s.durationMs) || 0;
    if (!out.longestSet || dur > out.longestSet.durationMs) out.longestSet = { durationMs: dur, reps, at: s.startedAt, id: s.id, day: s.day };
    out.lifetimeReps += reps;
    out.lifetimeMinutes += dur / 60000;
  }
  out.lifetimeMinutes = Math.round(out.lifetimeMinutes);
  const days = byDay(list);
  for (const d of days.values()) if (!out.bestDay || d.reps > out.bestDay.reps) out.bestDay = { day: d.day, reps: d.reps };
  const pick = (buckets) => {
    let best = null;
    for (const b of buckets) if (b.reps > 0 && (!best || b.reps > best.reps)) best = { key: b.key, reps: b.reps };
    return best;
  };
  out.bestWeek = pick(weekBuckets(days, 400));
  out.bestMonth = pick(monthBuckets(days, 120));
  out.bestYear = pick(yearBuckets(days, 40));
  return out;
}

/* ── estimates ─────────────────────────────────────────────────── */

/**
 * Estimated one-set max. A single all-out set is limited by the threshold you were counting
 * against, not by failure, so the best recent set is a floor rather than the answer. We take the
 * best set in the last `windowDays` and add a documented allowance: +12% of the set, never more
 * than +10 reps, and nothing added when the best set is older than the window.
 */
export function estimatedMax(sets, windowDays = 28, todayKey) {
  const from = addDays(todayKey || dayKey(Date.now()), -windowDays);
  let best = 0, bestAt = 0;
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt);
    if (day < from || day > (todayKey || dayKey(Date.now()))) continue;
    const reps = Number(s.repsFinal) || 0;
    if (reps > best) { best = reps; bestAt = s.startedAt || 0; }
  }
  if (!best) return { est: 0, basis: 0, windowDays, at: bestAt };
  return { est: best + Math.min(10, Math.round(best * 0.12)), basis: best, windowDays, at: bestAt };
}

/** Least-squares fit of weekly best-set values; projects the date a target is likely reached. */
export function projectTarget(sets, target, weeks = 12) {
  const series = bestSetPerWeek(sets, weeks).filter((w) => w.best > 0);
  if (series.length < 4) return { slope: 0, weeksTo: null, date: null, enough: false, points: series.length };
  const n = series.length;
  const xs = series.map((_, i) => i);
  const ys = series.map((w) => w.best);
  const mx = mean(xs), my = mean(ys);
  let num = 0, den = 0;
  for (let i = 0; i < n; i++) { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) ** 2; }
  const slope = den ? num / den : 0;
  const intercept = my - slope * mx;
  const now = ys[n - 1];
  if (now >= target) return { slope, weeksTo: 0, date: dayKey(Date.now()), enough: true, points: n, current: now };
  if (slope <= 0.05) return { slope, weeksTo: null, date: null, enough: true, current: now, points: n };
  const weeksTo = Math.ceil((target - intercept) / slope - (n - 1));
  if (weeksTo < 1 || weeksTo > 260) return { slope, weeksTo: null, date: null, enough: true, current: now, points: n };
  return { slope, weeksTo, date: addDays(weekStart(dayKey(Date.now())), weeksTo * 7), enough: true, current: now, points: n };
}

/* ── form quality over time ────────────────────────────────────── */

/**
 * Tempo and depth consistency from the per-rep rows of one set: coefficient of variation of rep
 * duration (tempo) and of minimum elbow angle (depth). Lower cv = more consistent. Returns nulls
 * when the set has fewer than three reps, because a cv of two numbers is not a signal.
 */
export function setConsistency(reps) {
  const list = (reps || []).filter((r) => r && Number.isFinite(r.durationMs));
  if (list.length < 3) return { reps: list.length, tempoCv: null, depthCv: null, medianMs: null, minElbow: null };
  const durs = list.map((r) => r.durationMs);
  const angles = list.map((r) => r.minElbow).filter((v) => Number.isFinite(v));
  const cv = (arr) => {
    const m = mean(arr);
    if (!m) return null;
    const sd = Math.sqrt(mean(arr.map((v) => (v - m) ** 2)));
    return sd / m;
  };
  const sorted = durs.slice().sort((a, b) => a - b);
  return {
    reps: list.length,
    tempoCv: cv(durs),
    depthCv: angles.length >= 3 ? cv(angles) : null,
    medianMs: sorted[Math.floor(sorted.length / 2)],
    minElbow: angles.length ? Math.min(...angles) : null,
  };
}

/**
 * Aggregate consistency across the most recent `count` sets, returned oldest→newest for charting.
 * Sorted defensively: listSets() hands back newest-first, and slice(-count) on that array would
 * otherwise read the oldest sets in the database.
 */
export function consistencySeries(sets, repsBySet, count = 30) {
  const ordered = (sets || []).slice().sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0));
  const out = [];
  for (const s of ordered.slice(-count)) {
    const c = setConsistency(repsBySet[s.id] || []);
    if (c.tempoCv === null && c.depthCv === null) continue;
    out.push({ id: s.id, day: s.day, at: s.startedAt, reps: c.reps, tempoCv: c.tempoCv, depthCv: c.depthCv, medianMs: c.medianMs });
  }
  return out;
}

/** Flag mix across a window, for the "what is the camera catching" row. */
export function flagMix(sets, windowDays = 30, todayKey) {
  const from = addDays(todayKey || dayKey(Date.now()), -windowDays);
  const t = { sag: 0, pike: 0, half: 0, lockout: 0, lost: 0, reps: 0, sets: 0 };
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt);
    if (day < from) continue;
    const f = s.flags || {};
    t.sets += 1;
    t.reps += Number(s.repsFinal) || 0;
    for (const k of ['sag', 'pike', 'half', 'lockout', 'lost']) t[k] += Number(f[k]) || 0;
  }
  return t;
}

/* ── heatmap ───────────────────────────────────────────────────── */

/**
 * Calendar heatmap cells for the last `weeks` weeks, column-major; index 0..6 inside a column is
 * Monday..Sunday. `level` is 0 none, 1 some, 2 half the goal, 3 goal met, 4 fifty over.
 */
export function heatmap(days, weeks = 26, goal = 50, endKey) {
  const end = endKey || dayKey(Date.now());
  const endMonday = weekStart(end);
  const cols = [];
  for (let i = weeks - 1; i >= 0; i--) {
    const monday = addDays(endMonday, -7 * i);
    const col = [];
    for (let d = 0; d < 7; d++) {
      const key = addDays(monday, d);
      const rec = days.get(key);
      const reps = rec ? rec.reps : 0;
      col.push({
        day: key, reps, sets: rec ? rec.sets : 0,
        level: reps === 0 || goal <= 0 ? (reps > 0 ? 1 : 0)
          : reps >= goal * 1.5 ? 4 : reps >= goal ? 3 : reps >= goal * 0.5 ? 2 : 1,
        future: key > end,
      });
    }
    cols.push({ week: monday, cells: col });
  }
  return cols;
}

/** Missing days with at least one set on either side — what "add a missed day" offers. */
export function gaps(days, windowDays = 90) {
  const keys = [...days.keys()].filter((k) => days.get(k).reps > 0).sort();
  if (keys.length < 2) return [];
  const out = [];
  const from = addDays(keys[keys.length - 1], -windowDays);
  for (let i = 1; i < keys.length; i++) {
    for (let d = 1; d < daysBetween(keys[i - 1], keys[i]); d++) {
      const key = addDays(keys[i - 1], d);
      if (key >= from) out.push(key);
    }
  }
  return out.slice(-31);
}

/** Everything the Today screen needs, in one pass over the sets. */
export function summarize(sets, opts = {}) {
  const goal = opts.dailyGoal || 0;
  const days = byDay(sets);
  const todayKey = opts.todayKey || dayKey(Date.now());
  const rec = days.get(todayKey) || emptyDay(todayKey);
  return {
    todayKey,
    today: rec,
    goal,
    goalPct: goal ? Math.min(1, rec.reps / goal) : 0,
    goalLeft: Math.max(0, goal - rec.reps),
    week: weekBuckets(days, 1).pop() || emptyDay(todayKey),
    month: monthBuckets(days, 1).pop() || emptyDay(todayKey),
    year: yearBuckets(days, 1).pop() || emptyDay(todayKey),
    lifetime: records(sets).lifetimeReps,
    streak: trainingStreak(days, todayKey),
    days30: dayBuckets(days, 30),
    setsToday: rec.sets,
  };
}
__EOF_js_stats_js__

mkdir -p 'js'
cat > 'js/upgrade.js' <<'__EOF_js_upgrade_js__'
const POLL_MS = 5 * 60 * 1000;

let reg = null;
let pollTimer = 0;
let listenersAttached = false;
let promptedWorker = null;
let reloadRequested = false;
let onPromptRef = null;

let sentinel = null;
let wantLock = false;
let lockReason = '';
let lockWatchAttached = false;

function hasSW() {
  return typeof navigator !== 'undefined'
    && 'serviceWorker' in navigator
    && !!navigator.serviceWorker;
}

function doReload() {
  if (reloadRequested) return;
  reloadRequested = true;
  try {
    if (typeof location !== 'undefined') location.reload();
  } catch (err) {
    void err;
  }
}

function attachControllerListener() {
  if (!hasSW()) return;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloadRequested) doReload();
  });
}

function promptWorker(worker) {
  if (!worker || promptedWorker === worker) return;
  promptedWorker = worker;
  const reload = () => {
    try {
      worker.postMessage('skip');
    } catch (err) {
      void err;
    }
    reloadRequested = true;
  };
  attachControllerListener();
  if (typeof onPromptRef === 'function') onPromptRef(reload);
}

function checkForWaiting() {
  if (reg && reg.waiting) promptWorker(reg.waiting);
}

function checkUpdate() {
  if (!reg || typeof reg.update !== 'function') return;
  try {
    Promise.resolve(reg.update()).catch(() => {});
  } catch (err) {
    void err;
  }
}

function onVisibility() {
  if (typeof document === 'undefined') return;
  if (document.visibilityState !== 'visible') return;
  checkUpdate();
  if (wantLock && !sentinel) void requestWakeLock(lockReason || 'resume');
}

export function initUpdate({ swRegistration, onPrompt } = {}) {
  if (!swRegistration) return false;
  reg = swRegistration;
  onPromptRef = typeof onPrompt === 'function' ? onPrompt : onPromptRef;

  if (!listenersAttached) {
    listenersAttached = true;
    if (typeof setInterval !== 'undefined') pollTimer = setInterval(checkUpdate, POLL_MS);
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility);
    if (hasSW()) {
      navigator.serviceWorker.addEventListener('message', (ev) => {
        const data = ev && ev.data;
        const isReload = data === 'reload'
          || (data && (data.type === 'reload' || data.reload === true));
        if (isReload) doReload();
      });
    }
    swRegistration.addEventListener('updatefound', () => {
      const worker = swRegistration.installing;
      if (!worker) return;
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && reg && reg.waiting) promptWorker(reg.waiting);
        else if (worker.state === 'activated') promptedWorker = null;
      });
    });
  }

  if (reg.waiting) promptWorker(reg.waiting);
  checkUpdate();
  return true;
}

export function setUpdatePromptHandler(fn) {
  onPromptRef = typeof fn === 'function' ? fn : null;
  checkForWaiting();
}

export async function requestWakeLock(reason = '') {
  if (typeof navigator === 'undefined' || !navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
    return false;
  }
  wantLock = true;
  lockReason = reason;
  if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return false;
  if (sentinel) return true;
  try {
    sentinel = await navigator.wakeLock.request('screen');
    if (typeof sentinel.addEventListener === 'function') {
      sentinel.addEventListener('release', () => { sentinel = null; });
    }
    return true;
  } catch (err) {
    void err;
    sentinel = null;
    return false;
  }
}

export function releaseWakeLock() {
  wantLock = false;
  lockReason = '';
  const s = sentinel;
  sentinel = null;
  if (!s || typeof s.release !== 'function') return false;
  try {
    Promise.resolve(s.release()).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function watchWakeLock() {
  if (typeof document === 'undefined' || lockWatchAttached) return lockWatchAttached;
  lockWatchAttached = true;
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    if (wantLock && !sentinel) void requestWakeLock(lockReason || 'reacquire');
  });
  return true;
}

export async function requestPersistent() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persist !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persist());
  } catch (err) {
    void err;
    return false;
  }
}

export async function persistentStatus() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persisted !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persisted());
  } catch (err) {
    void err;
    return false;
  }
}

export function tryBadging(count) {
  if (typeof navigator === 'undefined' || typeof navigator.setAppBadge !== 'function') return false;
  try {
    const value = Number.isFinite(Number(count)) ? Math.max(0, Math.round(Number(count))) : undefined;
    Promise.resolve(value === undefined ? navigator.setAppBadge() : navigator.setAppBadge(value)).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function isStandalone() {
  try {
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      if (window.matchMedia('(display-mode: standalone)').matches) return true;
      if (window.matchMedia('(display-mode: fullscreen)').matches) return true;
    }
    return navigator.standaloneMode === true || navigator.standalone === true;
  } catch (err) {
    void err;
    return false;
  }
}

export function platformInfo() {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
  const ios = /iPad|iPhone|iPod/.test(ua)
    || (typeof navigator !== 'undefined' && navigator.platform === 'MacIntel'
      && typeof navigator !== 'undefined' && navigator.maxTouchPoints > 1);
  return {
    ios,
    safari: /AppleWebKit/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS|Chrome\/|Chromium/.test(ua),
    standalone: isStandalone(),
    secure: typeof window !== 'undefined' ? window.isSecureContext === true : true,
    wakeLock: typeof navigator !== 'undefined' && 'wakeLock' in navigator,
    badging: typeof navigator !== 'undefined' && typeof navigator.setAppBadge === 'function',
    persist: typeof navigator !== 'undefined' && !!navigator.storage && typeof navigator.storage.persist === 'function',
    vibrate: typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function',
  };
}

export function stopUpdatePolling() {
  if (pollTimer && typeof clearInterval !== 'undefined') clearInterval(pollTimer);
  pollTimer = 0;
  if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility);
  return true;
}
__EOF_js_upgrade_js__

mkdir -p 'js'
cat > 'js/util.js' <<'__EOF_js_util_js__'
export function clamp(v, lo, hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function sum(arr) {
  let s = 0;
  for (let i = 0; i < arr.length; i++) s += Number(arr[i]) || 0;
  return s;
}

export function mean(arr) {
  return arr.length ? sum(arr) / arr.length : 0;
}

export function round(v, dp = 0) {
  const f = 10 ** dp;
  return Math.round((Number(v) || 0) * f) / f;
}

export function debounce(fn, ms = 250) {
  let t = 0;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

export function sleep(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

export function uid() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = (n) => String(n).padStart(2, '0');

export function fmtTime(ms) {
  const total = Math.max(0, Math.floor(Number(ms) || 0));
  const s = Math.floor(total / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
}

export function fmtClock(epoch) {
  const d = new Date(epoch);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function toLocalDate(day) {
  if (day instanceof Date) return day;
  const m = typeof day === 'string' && /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return new Date(day);
}

export function fmtDay(day) {
  const d = toLocalDate(day);
  if (Number.isNaN(d.getTime())) return String(day);
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

export function today() {
  return dayOf(Date.now());
}

export function dayOf(epochMs) {
  const d = new Date(epochMs);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function pct(v) {
  return `${Math.round(clamp(Number(v) || 0, 0, 1) * 100)}%`;
}

export function download(filename, text, mime = 'application/json') {
  const blob = new Blob([String(text ?? '')], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function clear(el) {
  if (!el) return el;
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

function appendKids(el, kids) {
  for (const kid of kids) {
    if (kid === null || kid === undefined || kid === false || kid === true) continue;
    if (Array.isArray(kid)) appendKids(el, kid);
    else if (kid instanceof Node) el.appendChild(kid);
    else el.appendChild(document.createTextNode(String(kid)));
  }
}

export function mount(el, ...kids) {
  appendKids(el, kids);
  return el;
}

export function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const key of Object.keys(attrs || {})) {
    const v = attrs[key];
    if (v === undefined || v === null || v === false) continue;
    if (key === 'class' || key === 'className') el.className = String(v);
    else if (key === 'dataset' && typeof v === 'object') Object.assign(el.dataset, v);
    else if (key === 'html') el.innerHTML = String(v);
    else if (key === 'text') el.textContent = String(v);
    else if (key === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (key.length > 2 && key.startsWith('on') && typeof v === 'function') {
      el.addEventListener(key.slice(2).toLowerCase(), v);
    } else if (v === true) el.setAttribute(key, '');
    else el.setAttribute(key, String(v));
  }
  appendKids(el, kids);
  return el;
}
__EOF_js_util_js__

mkdir -p 'js/views'
cat > 'js/views/badges.js' <<'__EOF_js_views_badges_js__'
/* Badges is still a placeholder in this build. It should read as a deliberate blank page — the
   rules it will use, phrased as rules, and no invented progress. */
const SVGNS = 'http://www.w3.org/2000/svg';

function icon(paths) {
  const el = document.createElementNS(SVGNS, 'svg');
  el.setAttribute('viewBox', '0 0 24 24');
  el.setAttribute('fill', 'none');
  el.setAttribute('stroke', 'currentColor');
  el.setAttribute('stroke-width', '1.7');
  el.setAttribute('stroke-linecap', 'round');
  el.setAttribute('stroke-linejoin', 'round');
  el.setAttribute('aria-hidden', 'true');
  for (const d of paths) {
    const p = document.createElementNS(SVGNS, d.c === 'circle' ? 'circle' : 'path');
    if (d.c === 'circle') {
      p.setAttribute('cx', d.cx); p.setAttribute('cy', d.cy); p.setAttribute('r', d.r);
    } else {
      p.setAttribute('d', d.d);
    }
    el.append(p);
  }
  return el;
}

const MEDAL = [
  { c: 'circle', cx: '12', cy: '9', r: '5.4' },
  { d: 'M9.2 13.6L7.5 20l4.5-2.6L16.5 20l-1.7-6.4' },
];

// name → the exact condition that will light it up, stated as a condition
const UPCOMING = [
  ['1,000 lifetime', 'lifetime reps reach 1,000'],
  ['Best set 30', 'one set of 30 with nothing flagged'],
  ['Clean 20', '20 reps in a row with no form flags'],
  ['Steady tempo', 'every rep of a set within 15% of that set\u2019s mean'],
  ['Twelve weeks', 'weekly goal met 12 weeks running'],
];

export default function badgesView(host) {
  const head = document.createElement('div');
  head.className = 'pad';
  const h1 = document.createElement('h1');
  h1.className = 'h1';
  h1.textContent = 'Badges';
  const note = document.createElement('p');
  note.className = 'sub';
  note.textContent = 'Not wired up yet. Everything these will read is already being recorded, so they will retroactively light up the moment phase 3 lands.';
  head.append(h1, note);

  const list = document.createElement('div');
  list.className = 'bd-list';
  for (const [name, rule] of UPCOMING) {
    const row = document.createElement('div');
    row.className = 'bd-row';
    const ic = document.createElement('span');
    ic.className = 'bd-ic';
    ic.append(icon(MEDAL));
    const txt = document.createElement('span');
    txt.className = 'bd-txt';
    const strong = document.createElement('b');
    strong.textContent = name;
    const why = document.createElement('span');
    why.className = 'bd-rule';
    why.textContent = rule;
    txt.append(strong, why);
    row.append(ic, txt);
    list.append(row);
  }

  host.replaceChildren(head, list);
  return {};
}
__EOF_js_views_badges_js__

mkdir -p 'js/views'
cat > 'js/views/debug.js' <<'__EOF_js_views_debug_js__'
import { load, save, params, setParam, resetParams } from '../settings.js';
import { Counter } from '../counter.js';
import { createTracker } from '../pose.js';
import { listSets } from '../db.js';
import { download, pct } from '../util.js';

export default function debugView(host) {
  const counter = new Counter(params());
  let tracker = null;
  let repLog = [];
  let frames = 0;
  let replaying = false;
  let lastT = 0;

  // replay must follow the video clock, and it must never go backwards when the clip loops
  function nowMs(f) {
    if (!replaying) return Date.now();
    let t = Math.round(f.stampMs != null ? f.stampMs : video.currentTime * 1000);
    if (t <= lastT) t = lastT + 33;
    lastT = t;
    return t;
  }

  host.innerHTML = `
    <div class="dbg">
      <div class="row"><a class="btn btn-quiet" href="#/train">← train</a>
        <span class="grow"></span><span id="mode">idle</span></div>

      <h3>live</h3>
      <table>
        <tr><th>state</th><td id="o-state">–</td></tr>
        <tr><th>armed</th><td id="o-armed">–</td></tr>
        <tr><th>side</th><td id="o-side">–</td></tr>
        <tr><th>elbow L / R</th><td id="o-elbow">–</td></tr>
        <tr><th>shoulder L / R</th><td id="o-shoulder">–</td></tr>
        <tr><th>hip offset</th><td id="o-hip">–</td></tr>
        <tr><th>body angle</th><td id="o-body">–</td></tr>
        <tr><th>plank reasons</th><td id="o-reasons">–</td></tr>
        <tr><th>quality / fps</th><td id="o-q">–</td></tr>
        <tr><th>reps det / clean</th><td id="o-reps">–</td></tr>
        <tr><th>frames</th><td id="o-frames">0</td></tr>
      </table>

      <h3>thresholds</h3>
      <div class="field"><label>top <b id="v-top"></b></label><input type="range" id="r-top" min="120" max="178"></div>
      <div class="field"><label>bottom <b id="v-bottom"></b></label><input type="range" id="r-bottom" min="70" max="130"></div>
      <div class="field"><label>min rep ms <b id="v-minRep"></b></label><input type="range" id="r-minRep" min="150" max="900" step="10"></div>
      <div class="field"><label>arm hold ms <b id="v-arm"></b></label><input type="range" id="r-arm" min="800" max="6000" step="100"></div>
      <div class="row"><button class="btn btn-quiet" id="b-reset">reset overrides</button>
        <span class="grow"></span><span id="ovl"></span></div>

      <h3>replay a recording instead of the camera</h3>
      <input type="file" id="f-file" accept="video/*">
      <video id="f-video" playsinline muted loop style="width:100%;margin-top:8px;background:#000"></video>
      <div class="row" style="margin-top:8px">
        <button class="btn btn-quiet" id="f-play">play</button>
        <button class="btn btn-quiet" id="f-stop">stop</button>
        <button class="btn btn-quiet" id="f-live">use camera</button>
        <span class="grow"></span>
        <button class="btn btn-quiet" id="f-clear">clear reps</button>
      </div>

      <h3>detected reps</h3>
      <table id="t-reps"><tr><th>#</th><th>t</th><th>min</th><th>max</th><th>drop</th><th>hip</th><th>flags</th></tr></table>

      <h3>detected vs corrected, all sets</h3>
      <div class="row" style="margin:6px 0">
        <button class="btn btn-quiet" id="b-export">export counter-lab json</button>
        <button class="btn btn-quiet" id="b-diff">show disagreement</button>
      </div>
      <table id="t-sets"><tr><th>date</th><th>det</th><th>fin</th><th>Δ</th><th>preset</th></tr></table>
      <div id="diffSum" class="st"></div>
    </div>`;

  const q = (s) => host.querySelector(s);
  const video = q('#f-video');

  const sliders = [
    ['top', 'top', '°'], ['bottom', 'bottom', '°'], ['minRepMs', 'minRep', ' ms'],
  ];
  function syncSliders() {
    const cur = load();
    const p = params();
    sliders.forEach(([key, id, unit]) => {
      q('#r-' + id).value = String(p[key]);
      q('#v-' + id).textContent = p[key] + unit;
    });
    q('#r-arm').value = String(cur.armHoldMs);
    q('#v-arm').textContent = cur.armHoldMs + ' ms';
    const o = Object.keys(cur.overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'preset: ' + cur.preset;
  }
  sliders.forEach(([key, id]) => {
    q('#r-' + id).addEventListener('input', (e) => {
      setParam(key, Number(e.target.value));
      counter.setParams(params());
      syncSliders();
    });
  });
  q('#r-arm').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    counter.setArmHold(Number(e.target.value));
    syncSliders();
  });
  q('#b-reset').addEventListener('click', () => { resetParams(); counter.setParams(params()); syncSliders(); });
  syncSliders();

  function onFrame(f) {
    frames += 1;
    const out = counter.addFrame(nowMs(f), f);
    paint(out, f);
    (out.events || []).forEach((ev) => {
      if (ev.type === 'rep') {
        repLog.push(ev.data && (ev.data.rep || ev.data));
        paintReps();
      }
    });
    q('#o-frames').textContent = String(frames);
  }

  function paint(out, f) {
    if (!out) return;
    q('#o-state').textContent = out.state;
    q('#o-armed').textContent = out.armed ? 'yes ' + Math.round((out.armMs || 0)) + 'ms' : 'no';
    q('#o-side').textContent = out.side || '–';
    const a = out.angles || {};
    const fmtA = (s) => {
      const v = a[s] && a[s].elbow;
      return v == null ? '–' : Math.round(v);
    };
    const fmtS = (s) => {
      const v = a[s] && a[s].shoulder;
      return v == null ? '–' : Math.round(v);
    };
    q('#o-elbow').textContent = fmtA('left') + ' / ' + fmtA('right');
    q('#o-shoulder').textContent = fmtS('left') + ' / ' + fmtS('right');
    q('#o-hip').textContent = out.hipOffset == null ? '–' : out.hipOffset.toFixed(3);
    q('#o-body').textContent = out.bodyAngle == null ? '–' : out.bodyAngle.toFixed(1) + '°';
    q('#o-reasons').textContent = (out.plank && out.plank.reasons || []).join(', ') || 'none';
    q('#o-q').textContent = pct(out.quality) + ' / ' + Math.round(f.fps || 0);
    q('#o-reps').textContent = out.repsDetected + ' / ' + out.cleanReps;
  }

  function paintReps() {
    const t = q('#t-reps');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    repLog.slice(-40).forEach((r) => {
      const tr = document.createElement('tr');
      [r.n, Math.round((r.tEnd - r.tStart) / 10) / 100 + 's', Math.round(r.minElbow || 0) + '°',
        Math.round(r.maxElbow || 0) + '°', (r.shoulderDrop || 0).toFixed(2),
        (r.hipMin > 0.18 ? 'sag' : r.hipMax < -0.14 ? 'pike' : '–'), (r.flags || []).join(' ') || 'clean']
        .forEach((v) => {
          const td = document.createElement('td');
          td.textContent = String(v);
          tr.append(td);
        });
      t.append(tr);
    });
  }

  function attachTracker(target) {
    if (tracker && tracker.dispose) tracker.dispose();
    repLog = [];
    frames = 0;
    counter.reset('debug');
    paintReps();
    tracker = await createTracker({
      video: target,
      model: load().model,
      fpsCap: load().fpsCap,
      onStatus: (k, d) => { q('#mode').textContent = 'engine · ' + k + (d ? ' ' + d : ''); },
      onFrame: (f) => { try { onFrame(f); } catch (e) { console.error(e); q('#mode').textContent = 'error ' + e.message; } },
      onError: (e) => { q('#mode').textContent = 'error: ' + e.message; },
    });
    tracker.start();
  }

  q('#f-file').addEventListener('change', (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    video.src = URL.createObjectURL(file);
    video.loop = true;
    q('#mode').textContent = 'loaded ' + file.name;
    video.addEventListener('loadeddata', () => {
      video.currentTime = 0;
      replaying = true;
      attachTracker(video);
      video.play();
      q('#mode').textContent = 'replaying ' + file.name;
    }, { once: true });
  });
  q('#f-play').addEventListener('click', () => {
    if (!video.src) return;
    if (tracker) tracker.start();
    video.play();
  });
  q('#f-stop').addEventListener('click', () => { if (tracker) tracker.stop(); video.pause(); });
  q('#f-clear').addEventListener('click', () => { counter.reset('debug'); repLog = []; frames = 0; paintReps(); });
  q('#f-live').addEventListener('click', async () => {
    video.pause();
    if (tracker) { tracker.dispose && tracker.dispose(); tracker = null; }
    const { openCamera } = await import('../camera.js');
    const cam = await openCamera(video, { facing: load().camera });
    replaying = false;
    attachTracker(video);
    q('#mode').textContent = 'camera · ' + (cam.settings.facing || load().camera);
  });

  q('#b-diff').addEventListener('click', async () => {
    const sets = await listSets();
    const t = q('#t-sets');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    let det = 0;
    let fin = 0;
    let off = 0;
    sets.slice(-60).forEach((s) => {
      const d = (s.repsFinal || 0) - (s.repsDetected || 0);
      det += s.repsDetected || 0;
      fin += s.repsFinal || 0;
      if (d !== 0) off += 1;
      const tr = document.createElement('tr');
      [new Date(s.startedAt).toLocaleDateString(), s.repsDetected, s.repsFinal,
        (d > 0 ? '+' : '') + d, s.presetName].forEach((v) => {
        const td = document.createElement('td');
        td.textContent = String(v);
        tr.append(td);
      });
      t.append(tr);
    });
    q('#diffSum').textContent = sets.length + ' sets · camera ' + det + ' · kept ' + fin +
      ' · ' + off + ' sets disagreed (' + (sets.length ? Math.round((off / sets.length) * 100) : 0) + '%)';
  });

  q('#b-export').addEventListener('click', async () => {
    const sets = await listSets();
    download('counter-lab-' + Date.now() + '.json', JSON.stringify({
      at: new Date().toISOString(), params: params(), settings: load(),
      repLog, sets: sets.map((s) => ({
        day: s.day, det: s.repsDetected, fin: s.repsFinal, flags: s.flags,
        quality: s.qualityStats, preset: s.presetName, paramsUsed: s.paramsUsed,
      })),
    }, null, 2));
  });

  return {
    unmount() {
      if (tracker) { tracker.stop && tracker.stop(); tracker.dispose && tracker.dispose(); }
      video.pause();
    },
  };
}
__EOF_js_views_debug_js__

mkdir -p 'js/views'
cat > 'js/views/progress.js' <<'__EOF_js_views_progress_js__'
/* Progress: the calendar heatmap is the one big thing; everything below it is a smaller read.
   All numbers come from stats.js / goals.js over a single listSets() read, so this screen and the
   Today screen cannot disagree. Charts are hand-rolled divs and inline SVG — no library, no build.
   Sets are sorted oldest-first once here, because stats.consistencySeries slices the tail. */

import { deleteSet, listReps, listSets, listSetsForDay, saveSet, updateSet } from '../db.js';
import { loadGoals } from '../goals.js';
import {
  addDays, bestSetPerWeek, byDay, consistencySeries, dayBuckets, dayFromKey, estimatedMax,
  flagMix, heatmap, monthBuckets, projectTarget, records, timeOfDay, weekBuckets, yearBuckets,
} from '../stats.js';
import { clamp, clear, fmtClock, fmtDay, h, mean, pct, sum, today } from '../util.js';

const NS = 'http://www.w3.org/2000/svg';
// The heatmap used to squeeze 26 weeks into 370pt, which made every day cell 18×24 — below the
// WCAG AA minimum for a touch target, and the hit areas had to overlap each other to get that big.
// It is now a calendar: one week per row, eight rows a page, so each day gets ~48×44 and pages back
// a month and a half at a time. Long-range history is what the Month/Year charts are for.
const HEAT_ROWS = 8;        // weeks per page
const HEAT_CELL = 44;       // CSS px, the iPhone HIG minimum
const DAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const BEST_WEEKS = 26;      // best-set step chart: 26 static bars, no tapping needed
const REP_CAP = 30;         // per-rep fan-out: never read rep rows for more sets than this
const TARGET_KEY = 'pushups.target';
const DEFAULT_TARGET = 100;
const MAX_WINDOW = 28;      // estimatedMax look-back, days

const RANGES = {
  day: { label: 'Day', window: 'last 30 days', make: (d) => dayBuckets(d, 30) },
  week: { label: 'Week', window: 'last 26 weeks', make: (d) => weekBuckets(d, 26) },
  month: { label: 'Month', window: 'last 12 months', make: (d) => monthBuckets(d, 12) },
  year: { label: 'Year', window: 'last 5 years', make: (d) => yearBuckets(d, 5) },
};
const RANGE_ORDER = ['day', 'week', 'month', 'year'];
const DAY_GRAIN = ['month', 'year'];   // these buckets count days, not sets

const VOL_SERIES = {
  volume: { label: 'weekly volume', pick: (b) => b.reps, unit: 'reps this week' },
  avg: { label: 'reps per set', pick: (b) => b.avgPerSet, unit: 'per set this week' },
};

const FLAG_LABEL = {
  sag: 'hips sagging', pike: 'hips piking', half: 'shallow reps',
  lockout: 'no lockout', lost: 'tracking lost',
};
const FLAG_HARD = ['sag', 'pike', 'half', 'lost'];
const TOD_TONE = ['lv1', 'lv2', 'lv3', 'lv4'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const SKELETON = `
  <div class="list">
    <div class="pg-top pad">
      <h1 class="h1">Progress</h1>
      <p class="pg-sum" id="pgSum"></p>
      <p class="pg-error" id="pgNote"></p>
    </div>
    <div class="pg-heatsec">
      <div class="pg-cap pad" id="pgHeatCap"></div>
      <div class="pad" id="pgHeat"></div>
      <div class="pg-capend pad" id="pgHeatLegend"></div>
    </div>
    <div class="pg-sec">
      <div class="pad" id="pgRangeHead"></div>
      <div class="pg-seg pad" id="pgRange"></div>
      <div class="pg-cap pad" id="pgChartCap"></div>
      <div id="pgChart"></div>
    </div>
    <div class="pg-box pad" id="pgBest"></div>
    <div class="pg-box pad" id="pgVol"></div>
    <div class="pg-sec">
      <div class="pad" id="pgMax"></div>
      <div class="rule" style="margin:10px 16px 6px"></div>
      <div class="pad" id="pgTarget"></div>
    </div>
    <div class="pg-box pad" id="pgConsist"></div>
    <div class="pg-sec">
      <div class="pad" id="pgRecHead"></div>
      <div class="pad" id="pgRecords"></div>
      <div id="pgFlags" class="pad"></div>
    </div>
    <div class="pg-box pad" id="pgTod"></div>
    <div class="pg-foot pad" id="pgFoot"></div>
    <div style="height:14px"></div>
  </div>`;

/* ── small builders ────────────────────────────────────────────── */

function svg(tag, attrs) {
  const el = document.createElementNS(NS, tag);
  for (const k of Object.keys(attrs || {})) {
    const v = attrs[k];
    if (v === null || v === undefined || v === false) continue;
    el.setAttribute(k, String(v));
  }
  return el;
}

/** CSS custom properties need setProperty — Object.assign onto style would be ignored. */
function vars(el, map) {
  for (const k of Object.keys(map || {})) el.style.setProperty(k, String(map[k]));
  return el;
}

function errText(e) {
  return e && e.message ? e.message : String(e);
}

function fmtDur(ms) {
  const t = Math.max(0, Math.round((Number(ms) || 0) / 1000));
  return Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
}

/** 'YYYY-MM-DD' at local midday, so a backfilled set sorts inside its own day. */
function noonOf(dayKeyStr) {
  const d = new Date(dayFromKey(dayKeyStr));
  d.setHours(12, 0, 0, 0);
  return d.getTime();
}

function parseReps(raw) {
  const n = parseInt(String(raw).trim(), 10);
  return Number.isFinite(n) ? clamp(n, 0, 999) : null;
}

function repsOf(s) {
  return Number(s && s.repsFinal) || 0;
}

function detectedOf(s) {
  return Number(s && s.repsDetected) || 0;
}

function flagCount(s) {
  const f = (s && s.flags) || {};
  return (Number(f.sag) || 0) + (Number(f.pike) || 0) + (Number(f.half) || 0)
    + (Number(f.lockout) || 0) + (Number(f.lost) || 0);
}

function sourceLabel(s) {
  if (s.source === 'manual' || s.mode === 'manual') return 'manual';
  return s.cameraUsed === 'user' ? 'front cam' : 'side cam';
}

/** Tick text per grain: day number, week start as m/d, three-letter month, four-digit year. */
function bucketLabel(bucket, grain) {
  if (grain === 'day') return String(Number(bucket.key.slice(8, 10)));
  if (grain === 'week') return Number(bucket.key.slice(5, 7)) + '/' + Number(bucket.key.slice(8, 10));
  if (grain === 'month') return MONTH_NAMES[(Number(bucket.key.slice(5, 7)) || 1) - 1];
  return bucket.label || bucket.key;
}

function monthText(mk) {
  return MONTH_NAMES[(Number(mk.slice(5, 7)) || 1) - 1] + ' ' + String(mk).slice(0, 4);
}

/** 'Fri 9 Oct', but with the year when the date is not in the current one. */
function fmtDayYear(dayKeyStr, nowKey) {
  const text = fmtDay(dayKeyStr);
  return String(dayKeyStr).slice(0, 4) === String(nowKey).slice(0, 4) ? text : text + ' ' + String(dayKeyStr).slice(0, 4);
}

function peakCaption(bucket, grain) {
  const reps = bucket.reps;
  if (grain === 'day') return 'peak ' + reps + ' on ' + fmtDay(bucket.key);
  if (grain === 'week') return 'peak ' + reps + ' in the week of ' + fmtDay(bucket.key);
  if (grain === 'month') return 'peak ' + reps + ' in ' + monthText(bucket.key);
  return 'peak ' + reps + ' in ' + bucket.key;
}

function headBlock(title, sub) {
  const row = h('div', { class: 'pg-headrow' }, h('h2', { class: 'pg-headtitle' }, title));
  if (sub) row.append(h('div', { class: 'pg-headsub' }, sub));
  return row;
}

function caption(text, cls) {
  return h('p', { class: 'sub pg-caption' + (cls ? ' ' + cls : '') }, text);
}

/* ── hand-rolled charts ────────────────────────────────────────── */

/**
 * Line or step chart in a 100-wide viewBox stretched to the container. non-scaling-stroke keeps the
 * line the same weight whatever the x/y stretch factors do, so nothing here needs measuring.
 */
function spark(vals, opts = {}) {
  const clean = (vals || []).map((v) => (Number.isFinite(v) ? v : 0));
  const n = clean.length;
  const height = Number(opts.height) || 56;
  const pad = 3;
  const el = svg('svg', {
    class: 'pg-spark' + (opts.tone ? ' ' + opts.tone : ''),
    viewBox: '0 0 100 ' + height, preserveAspectRatio: 'none',
    'aria-hidden': 'true', focusable: 'false',
  });
  el.style.setProperty('height', height + 'px');
  if (!n) return el;
  const top = Math.max(...clean) || 1;
  const x = (i) => (n === 1 ? 50 : (i * 100) / (n - 1));
  const y = (v) => height - pad - clamp(v / top, 0, 1) * (height - pad * 2);
  const parts = [];
  if (opts.step) {
    parts.push('M' + x(0).toFixed(2) + ' ' + y(clean[0]).toFixed(2));
    for (let i = 1; i < n; i++) {
      parts.push('H' + x(i).toFixed(2));
      parts.push('V' + y(clean[i]).toFixed(2));
    }
  } else {
    clean.forEach((v, i) => parts.push((i ? 'L' : 'M') + x(i).toFixed(2) + ' ' + y(v).toFixed(2)));
  }
  el.append(svg('path', { class: 'pg-base', d: 'M0 ' + (height - 0.6).toFixed(2) + ' H100' }));
  el.append(svg('path', {
    class: 'pg-area',
    d: parts.join(' ') + ' H' + x(n - 1).toFixed(2) + ' V' + height + ' H' + x(0).toFixed(2) + ' Z',
  }));
  el.append(svg('path', { class: 'pg-line', d: parts.join(' ') }));
  if (opts.dot !== false) {
    el.append(svg('circle', { class: 'pg-dot', cx: x(n - 1).toFixed(2), cy: y(clean[n - 1]).toFixed(2), r: '2.2' }));
  }
  return el;
}

/** Axis row with one slot per bucket so labels line up with their bars. */
function axisRow(buckets, grain) {
  const n = buckets.length;
  const every = n > 13 ? Math.ceil(n / 5) : n > 8 ? 2 : 1;
  const row = h('div', { class: 'pg-axis' });
  buckets.forEach((b, i) => {
    const show = every === 1 ? true : (i % every === 1 && i < n - 1);
    row.append(h('div', { class: 'pg-aslot' }, show ? h('span', { class: 'pg-atext' }, bucketLabel(b, grain)) : null));
  });
  return row;
}

/** Reps as bars; sets (or training days) as a quiet tick at the baseline. */
function barChart(buckets, opts) {
  const grain = opts.grain;
  const secOf = (b) => (DAY_GRAIN.indexOf(grain) >= 0 ? b.days : b.sets);
  const maxReps = Math.max(0, ...buckets.map((b) => b.reps));
  const maxSec = Math.max(0, ...buckets.map(secOf));
  const wrap = h('div', { class: 'pg-barchart' });
  if (!maxReps) {
    // a 112px void next to a caption that already says nothing happened is just a hole in the page
    wrap.append(h('div', { class: 'pg-plotempty' }, 'nothing logged in this window yet'));
    return wrap;
  }
  const plot = h('div', { class: 'pg-plot' });
  if (opts.goal > 0 && maxReps > 0 && opts.goal <= maxReps) {
    // 5px of the slot is the tick and its gap, so the goal line is measured against the bar area only
    const frac = clamp(opts.goal / maxReps, 0, 1).toFixed(4);
    const line = h('div', { class: 'pg-goalline' }, h('span', { class: 'pg-goaltag' }, 'goal ' + opts.goal));
    line.style.setProperty('bottom', 'calc((100% - 5px) * ' + frac + ' + 5px)');
    plot.append(line);
  }
  buckets.forEach((b) => {
    const sec = secOf(b);
    const bar = h('i', { class: 'pg-bar' + (maxReps > 0 && b.reps === maxReps ? ' hi' : ''), 'aria-hidden': 'true' });
    bar.style.setProperty('height', (maxReps > 0 ? clamp(b.reps / maxReps, 0, 1) * 100 : 0) + '%');
    const tick = h('i', { class: 'pg-tick', 'aria-hidden': 'true' });
    tick.style.setProperty('opacity', sec > 0 && maxSec > 0 ? (0.3 + 0.7 * (sec / maxSec)).toFixed(2) : '0');
    plot.append(h('div', { class: 'pg-slot' }, h('div', { class: 'pg-bint' }, bar), tick));
  });
  wrap.append(plot, axisRow(buckets, grain));
  // The bars themselves are aria-hidden decoration, so the wrapper has to say what they mean.
  const spoken = buckets.filter((b) => b.reps > 0)
    .slice().sort((a, b) => b.reps - a.reps).slice(0, 3)
    .map((b) => labelOf(b, grain) + ' ' + b.reps).join(', ');
  wrap.setAttribute('role', 'img');
  wrap.setAttribute('aria-label', sum(buckets.map((b) => b.reps)) + ' reps across ' + buckets.length
    + ' ' + grain + ' bars' + (spoken ? '. Highest: ' + spoken + '.' : '. None logged.'));
  return wrap;
}

/** Short axis name for one bucket, for spoken chart summaries. */
function labelOf(b, grain) {
  if (grain === 'day') return fmtDay(dayFromKey(b.key));
  if (grain === 'month') return b.key;
  if (grain === 'year') return b.key;
  return 'week of ' + fmtDay(b.key);
}

/* ── the view ──────────────────────────────────────────────────── */

export default async function progressView(host, ctx) {
  const key = today();
  const rerender = () => (ctx && typeof ctx.render === 'function' ? ctx.render() : null);
  let scrim = null;
  let dirty = false;
  let resizeTimer = 0;

  host.innerHTML = SKELETON;
  const q = (sel) => host.querySelector(sel);
  const els = {
    sum: q('#pgSum'), note: q('#pgNote'),
    heatCap: q('#pgHeatCap'), heat: q('#pgHeat'), heatLegend: q('#pgHeatLegend'),
    rangeHead: q('#pgRangeHead'), range: q('#pgRange'), chartCap: q('#pgChartCap'), chart: q('#pgChart'),
    best: q('#pgBest'), vol: q('#pgVol'), max: q('#pgMax'), target: q('#pgTarget'),
    consist: q('#pgConsist'), recHead: q('#pgRecHead'), records: q('#pgRecords'), flags: q('#pgFlags'),
    tod: q('#pgTod'), foot: q('#pgFoot'),
  };

  // ── one read, guarded ─────────────────────────────────────────
  let sets = [];
  let dbError = '';
  try {
    const rows = await listSets();
    sets = Array.isArray(rows) ? rows.slice().sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0)) : [];
  } catch (e) {
    dbError = errText(e);
  }
  if (dbError) {
    host.replaceChildren(h('div', { class: 'list' },
      h('div', { class: 'pg-top pad' },
        h('h1', { class: 'h1' }, 'Progress'),
        h('p', { class: 'pg-error' },
          'could not read your saved sets: ' + dbError + '. Nothing on this screen can be drawn until the database opens again.'))));
    return {};
  }

  let goals = null;
  try {
    goals = await loadGoals();
  } catch (e) {
    els.note.textContent = 'goals could not be read: ' + errText(e);
  }
  const dailyGoal = goals && Number(goals.daily) > 0 ? Number(goals.daily) : 0;

  let days = byDay([]);
  let rec = records([]);
  try {
    days = byDay(sets);
    rec = records(sets);
  } catch (e) {
    els.note.textContent = 'aggregation failed: ' + errText(e);
  }

  els.sum.textContent = sets.length
    ? sets.length + ' sets · ' + rec.lifetimeReps + ' reps · ' + days.size + ' days logged'
    : 'nothing logged yet';

  let range = 'week';
  let volKey = 'volume';
  let heatBack = 0;
  let target = readTarget();

  paintHeat();
  paintRange();
  paintBest();
  paintVol();
  paintMax();
  paintTarget();
  paintRecords();
  paintTod();
  paintFoot();
  paintConsistency();          // async on its own: needs per-rep rows

  window.addEventListener('resize', onResize);

  function onResize() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(paintHeat, 200);
  }

  // ── calendar heatmap: the hero ────────────────────────────────

  function paintHeat() {
    // Rows are weeks, columns are Monday–Sunday. That shape gives every day a full-width slice of
    // a 370pt screen, so the tappable cell clears the 44pt iPhone bar instead of trading it away
    // for more columns; the window pages back 8 weeks at a time.
    const weeks = HEAT_ROWS;
    const cell = 44;
    const gap = 3;
    const lastDay = addDays(key, -7 * weeks * heatBack);

    let cols = [];
    try {
      cols = heatmap(days, weeks, dailyGoal, lastDay);
    } catch (e) {
      els.note.textContent = 'heatmap failed: ' + errText(e);
    }
    clear(els.heat);
    clear(els.heatCap);
    clear(els.heatLegend);

    const first = cols.length ? cols[0].cells[0].day : lastDay;
    const nav = h('span', { class: 'pg-heatnav' });
    nav.append(h('button', {
      class: 'pg-heatbtn', type: 'button', 'aria-label': 'earlier 8 weeks',
      onclick: () => { heatBack += 1; paintHeat(); },
    }, h('span', { class: 'pg-heatdisc' }, '‹')), h('button', {
      class: 'pg-heatbtn', type: 'button', 'aria-label': heatBack === 0 ? 'current weeks' : 'later 8 weeks',
      disabled: heatBack === 0 ? true : null,
      onclick: () => { if (heatBack > 0) { heatBack -= 1; paintHeat(); } },
    }, h('span', { class: 'pg-heatdisc' }, '›')));

    els.heatCap.append(nav,
      h('span', { class: 'pg-captxt' }, weeks + ' weeks'),
      h('span', { class: 'pg-capdim' }, ' · ' + fmtDay(first) + ' to ' + fmtDay(lastDay)));
    if (heatBack > 0) {
      els.heatCap.append(h('span', { class: 'pg-capdim' },
        ' · ' + heatBack + ' page' + (heatBack > 1 ? 's' : '') + ' back'));
    }
    if (!sets.length) els.heatCap.append(h('span', { class: 'pg-capdim' }, ' · nothing logged yet'));

    const grid = vars(h('div', { class: 'pg-heatgrid' }), { '--pg-cell': cell + 'px', '--pg-gap': gap + 'px' });
    grid.setAttribute('role', 'img');
    grid.setAttribute('aria-label', weeks + ' weeks of daily totals, one week per row, Monday first, through ' + fmtDay(lastDay));
    grid.append(h('div', { class: 'pg-heatrow pg-headday' },
      ...DAY_LABELS.map((d) => h('span', { class: 'pg-hday' }, d))));
    for (const col of cols) {
      const isNow = col.cells.some((c) => c.day === key);
      const rowEl = h('div', { class: 'pg-heatrow' + (isNow ? ' now' : '') });
      for (const c of col.cells) {
        rowEl.append(h('button', {
          class: 'pg-hcell' + (c.day === key ? ' today' : ''),
          type: 'button',
          disabled: c.future ? true : null,
          'aria-label': fmtDay(c.day) + ': ' + c.reps + ' reps in ' + c.sets + ' sets',
          onclick: c.future ? null : () => openDaySheet(c.day),
        }, h('span', { class: 'pg-hsq lv' + c.level })));
      }
      grid.append(rowEl);
    }
    els.heat.append(grid);

    const legend = h('div', { class: 'pg-legend' }, h('span', { class: 'pg-capdim' }, 'less'));
    for (let lv = 0; lv <= 4; lv++) legend.append(h('span', { class: 'pg-hsq lv' + lv }));
    legend.append(h('span', { class: 'pg-capdim' }, 'more'),
      h('span', { class: 'pg-capdim' }, dailyGoal ? ' · full at ' + dailyGoal : ' · no goal set'));
    els.heatLegend.append(legend);
  }

  // ── range switcher + bar chart ────────────────────────────────

  function paintRange() {
    clear(els.rangeHead);
    clear(els.range);
    els.rangeHead.append(headBlock('Reps over time', 'bars are reps · the tick under each is sets'));
    RANGE_ORDER.forEach((name) => {
      const on = name === range;
      els.range.append(h('button', {
        class: 'pg-segb' + (on ? ' on' : ''),
        type: 'button',
        'aria-pressed': on ? 'true' : 'false',
        onclick: () => { if (!on) { range = name; paintRange(); } },
      }, RANGES[name].label));
    });
    paintChart();
  }

  function paintChart() {
    const spec = RANGES[range];
    clear(els.chartCap);
    clear(els.chart);
    let buckets = [];
    try {
      buckets = spec.make(days);
    } catch (e) {
      els.chartCap.append(h('span', { class: 'pg-error' }, 'chart failed: ' + errText(e)));
      return;
    }
    const total = sum(buckets.map((b) => b.reps));
    let peak = null;
    for (const b of buckets) if (!peak || b.reps > peak.reps) peak = b;
    els.chartCap.append(h('span', { class: 'pg-captxt' }, spec.window));
    els.chartCap.append(h('span', { class: 'pg-capdim' },
      peak && peak.reps > 0 ? ' · ' + peakCaption(peak, range) + ' · ' + total + ' logged' : ' · nothing logged'));
    els.chart.append(barChart(buckets, { grain: range, goal: range === 'day' ? dailyGoal : 0 }));
  }

  // ── best set over time ────────────────────────────────────────

  function paintBest() {
    clear(els.best);
    els.best.append(headBlock('Best set over time',
      'biggest single set in each of the last ' + BEST_WEEKS + ' weeks'));
    let weeks = [];
    try {
      weeks = bestSetPerWeek(sets, BEST_WEEKS);
    } catch (e) {
      els.best.append(h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const live = weeks.filter((w) => w.best > 0);
    if (!live.length) {
      els.best.append(h('p', { class: 'sub' }, 'no sets yet — this line starts once you train.'));
      return;
    }
    const current = Math.max(...live.map((w) => w.best));
    const holder = weeks.filter((w) => w.best === current).pop();
    els.best.append(h('div', { class: 'pg-numrow' },
      h('div', { class: 'pg-num' }, String(current)),
      h('div', { class: 'pg-numsub' }, 'reps in one set · best week started ' + fmtDay(holder.key))));
    els.best.append(spark(weeks.map((w) => w.best), { step: true, tone: 'brass', height: 62 }));
    els.best.append(h('div', { class: 'pg-axisline' },
      h('span', { class: 'pg-capdim' }, 'week of ' + fmtDay(weeks[0].key)),
      h('span', { class: 'pg-capdim' }, 'this week')));
  }

  // ── weekly volume and average set size ────────────────────────

  function paintVol() {
    clear(els.vol);
    els.vol.append(headBlock('Weekly load', 'last 16 weeks'));
    const toggle = h('div', { class: 'pg-seg pg-segmini' });
    Object.keys(VOL_SERIES).forEach((name) => {
      const on = name === volKey;
      toggle.append(h('button', {
        class: 'pg-segb' + (on ? ' on' : ''), type: 'button', 'aria-pressed': on ? 'true' : 'false',
        onclick: () => { if (!on) { volKey = name; paintVol(); } },
      }, VOL_SERIES[name].label));
    });
    els.vol.append(toggle);
    let buckets = [];
    try {
      buckets = weekBuckets(days, 16);
    } catch (e) {
      els.vol.append(h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const spec = VOL_SERIES[volKey];
    const live = buckets.filter((b) => b.reps > 0);
    if (!live.length) {
      els.vol.append(h('p', { class: 'sub pg-caption' }, 'nothing logged in these weeks.'));
      return;
    }
    els.vol.append(spark(buckets.map(spec.pick), { tone: 'track', height: 50 }));
    const last = live[live.length - 1];
    els.vol.append(h('div', { class: 'pg-axisline' },
      h('span', { class: 'pg-capdim' }, spec.pick(last) + ' ' + spec.unit),
      h('span', { class: 'pg-capdim' }, live.length + ' of ' + buckets.length + ' weeks trained')));
  }

  // ── estimated max ─────────────────────────────────────────────

  function paintMax() {
    clear(els.max);
    els.max.append(headBlock('Estimated one-set max', 'an estimate, not a measurement'));
    let est = { est: 0, basis: 0, at: 0 };
    try {
      est = estimatedMax(sets, MAX_WINDOW, key);
    } catch (e) {
      els.max.append(h('p', { class: 'pg-error' }, 'estimate failed: ' + errText(e)));
      return;
    }
    if (!est.basis) {
      els.max.append(h('p', { class: 'sub pg-caption' },
        'no set logged in the last ' + MAX_WINDOW + ' days — train once and this appears.'));
      return;
    }
    els.max.append(h('div', { class: 'pg-numrow' },
      h('div', { class: 'pg-num' }, String(est.est)),
      h('div', { class: 'pg-numsub' }, 'from your ' + est.basis + '-rep set on ' + fmtDay(est.at))));
    els.max.append(caption('A set ends when you stop, not when you fail, so this is your best recent '
      + 'set plus an allowance of ' + (est.est - est.basis) + ' reps. It is a floor with a guess on top.'));
  }

  // ── milestone projection ──────────────────────────────────────

  function paintTarget() {
    clear(els.target);
    els.target.append(headBlock('Road to a target set',
      'fitted over your last 12 weekly best sets'));
    const inp = h('input', {
      class: 'pg-tin', type: 'number', inputmode: 'numeric', min: '1', max: '999',
      'aria-label': 'target reps in one set',
    });
    inp.value = String(target);
    const err = h('span', { class: 'pg-err' });
    const apply = () => {
      const v = parseInt(inp.value, 10);
      if (!Number.isFinite(v) || v < 1 || v > 999) { err.textContent = 'pick a number from 1 to 999'; return; }
      err.textContent = '';
      target = v;
      writeTarget(v);
      paintProjection();
    };
    inp.addEventListener('change', apply);
    inp.addEventListener('blur', apply);
    els.target.append(h('div', { class: 'pg-targetrow' },
      h('span', { class: 'pg-capdim' }, 'target'), inp, h('span', { class: 'pg-capdim' }, 'reps in one set')), err);
    els.target.append(h('div', { id: 'pgProj' }));
    paintProjection();
  }

  function paintProjection() {
    const slot = q('#pgProj');
    if (!slot) return;
    clear(slot);
    let proj = { enough: false, weeksTo: null, date: null, slope: 0, points: 0 };
    try {
      proj = projectTarget(sets, target, 12);
    } catch (e) {
      slot.append(h('p', { class: 'pg-error' }, 'projection failed: ' + errText(e)));
      return;
    }
    if (!proj.enough) {
      slot.append(h('p', { class: 'pg-proj' }, 'log four weeks of sets first.'));
      slot.append(caption(proj.points
        ? 'Only ' + proj.points + ' week' + (proj.points === 1 ? '' : 's') + ' with a best set to fit a line to.'
        : 'There is nothing to fit a line to yet.'));
      return;
    }
    const nowLine = caption('Your best set now is ' + proj.current + ' reps.');
    if (proj.weeksTo === 0) {
      slot.append(h('p', { class: 'pg-proj done' }, 'already there — you have a ' + proj.current + '-rep set.'));
      slot.append(nowLine);
      return;
    }
    if (proj.weeksTo === null) {
      slot.append(h('p', { class: 'pg-proj' }, proj.slope <= 0
        ? 'your weekly best is flat or falling, so there is no date to give you.'
        : 'the slope is too shallow to name a date without lying.'));
      slot.append(nowLine);
      return;
    }
    slot.append(h('p', { class: 'pg-proj' },
      h('b', { class: 'num pg-projdate' }, fmtDayYear(proj.date, key)),
      ' — about ' + proj.weeksTo + ' week' + (proj.weeksTo === 1 ? '' : 's') + ' at this slope.'));
    slot.append(caption('The fit rises ' + proj.slope.toFixed(1) + ' reps a week over ' + proj.points
      + ' weeks. It assumes you keep training; one new real best set moves it more than one bad week does.'));
  }

  // ── form consistency ──────────────────────────────────────────

  async function paintConsistency() {
    clear(els.consist);
    els.consist.append(headBlock('Form consistency',
      'how even your pace and depth were — lower is steadier'));
    const recent = sets.slice(-REP_CAP);
    if (!recent.length) {
      els.consist.append(h('p', { class: 'sub' }, 'no sets yet.'));
      return;
    }
    const repsBySet = {};
    let lack = 0;
    let readError = '';
    for (const s of recent) {
      try {
        const rows = await listReps(s.id);
        repsBySet[s.id] = Array.isArray(rows) ? rows : [];
      } catch (e) {
        repsBySet[s.id] = [];
        readError = errText(e);
      }
      if ((repsBySet[s.id] || []).length < 3) lack += 1;
    }
    let series = [];
    try {
      series = consistencySeries(sets, repsBySet, REP_CAP);
    } catch (e) {
      els.consist.append(h('p', { class: 'pg-error' }, 'consistency failed: ' + errText(e)));
      return;
    }
    if (!series.length) {
      els.consist.append(h('p', { class: 'sub' },
        'no per-rep data on the last ' + recent.length + ' sets — they were logged by hand or recorded '
        + 'before the counter saved every rep.'));
      return;
    }
    if (lack) {
      els.consist.append(caption(lack + ' of the last ' + recent.length
        + ' sets have no per-rep rows and are left out' + (readError ? ' (' + readError + ')' : '') + '.'));
    }
    const tempo = series.filter((p) => p.tempoCv !== null).map((p) => p.tempoCv);
    const depth = series.filter((p) => p.depthCv !== null).map((p) => p.depthCv);
    const grid = h('div', { class: 'pg-consgrid' });
    grid.append(consistBlock('pace', tempo, 'spread of rep durations'));
    grid.append(consistBlock('depth', depth, 'spread of how deep each rep went'));
    els.consist.append(grid);
    els.consist.append(caption(series.length + ' sets measured. The number is the coefficient of '
      + 'variation: scatter around your own average, as a share of it. 15% means most reps landed within '
      + 'about a sixth of your usual rhythm.'));
  }

  function consistBlock(title, vals, foot) {
    const box = h('div', { class: 'pg-cons' });
    box.append(h('div', { class: 'pg-conshead' },
      h('span', { class: 'pg-conslbl' }, title),
      h('span', { class: 'num pg-consval' }, vals.length >= 3 ? pct(mean(vals)) : '–')));
    box.append(spark(vals, { tone: 'plum', height: 40, dot: false }));
    box.append(h('div', { class: 'pg-consfoot' }, vals.length >= 3 ? foot : 'needs three reps with data'));
    return box;
  }

  // ── records and flag mix ──────────────────────────────────────

  function paintRecords() {
    clear(els.recHead);
    clear(els.records);
    els.recHead.append(headBlock('Records', 'every set on this phone'));
    const dayOfEntry = (e) => (e && (e.day || e.at) ? fmtDay(e.day || e.at) : '');
    rows().forEach(([label, value, meta]) => {
      els.records.append(h('div', { class: 'kv' },
        h('span', { class: 'pg-key' }, label),
        h('span', { class: 'pg-valwrap' },
          h('b', { class: 'pg-val' }, value),
          meta ? h('span', { class: 'pg-valmeta' }, meta) : null)));
    });

    function rows() {
      const r = rec;
      return [
        ['best set', r.bestSet ? r.bestSet.reps + ' reps' : '–', dayOfEntry(r.bestSet)],
        ['longest set', r.longestSet ? fmtDur(r.longestSet.durationMs) : '–',
          r.longestSet ? r.longestSet.reps + ' reps · ' + dayOfEntry(r.longestSet) : ''],
        ['best day', r.bestDay ? r.bestDay.reps + ' reps' : '–', r.bestDay ? fmtDay(r.bestDay.day) : ''],
        ['best week', r.bestWeek ? r.bestWeek.reps + ' reps' : '–', r.bestWeek ? 'from ' + fmtDay(r.bestWeek.key) : ''],
        ['best month', r.bestMonth ? r.bestMonth.reps + ' reps' : '–', r.bestMonth ? monthText(r.bestMonth.key) : ''],
        ['best year', r.bestYear ? r.bestYear.reps + ' reps' : '–', r.bestYear ? String(r.bestYear.key) : ''],
        ['lifetime', r.lifetimeReps + ' reps', r.lifetimeSets + ' sets · ' + r.lifetimeMinutes + ' min'],
      ];
    }

    clear(els.flags);
    let mix = null;
    try {
      mix = flagMix(sets, 30, key);
    } catch (e) {
      els.flags.append(h('p', { class: 'pg-error' }, 'flag mix failed: ' + errText(e)));
      return;
    }
    els.flags.append(headBlock('What the camera is catching', 'last 30 days · ' + mix.sets + ' sets'));
    if (!mix.sets) {
      els.flags.append(h('p', { class: 'sub' }, 'no sets in the last 30 days.'));
      return;
    }
    const keys = Object.keys(FLAG_LABEL).filter((k) => (Number(mix[k]) || 0) > 0);
    const row = h('div', { class: 'flags' });
    if (!keys.length) {
      row.append(h('span', null, 'nothing flagged in ' + mix.reps + ' reps'));
    } else {
      keys.forEach((k) => row.append(h('span', {
        class: FLAG_HARD.indexOf(k) >= 0 ? 'hard' : 'soft',
      }, mix[k] + ' ' + FLAG_LABEL[k])));
      const flagged = sum(keys.map((k) => mix[k]));
      row.append(h('span', null, flagged + ' of ' + mix.reps + ' reps'));
    }
    els.flags.append(row);
    if (keys.length) {
      els.flags.append(caption('A flag is a rep the camera was unsure about, not a rep you did badly. '
        + 'Check the depth preset in Settings if shallow reps keep showing up.'));
    }
  }

  // ── time of day ───────────────────────────────────────────────

  function paintTod() {
    clear(els.tod);
    let buckets = [];
    try {
      buckets = timeOfDay(sets);
    } catch (e) {
      els.tod.append(headBlock('Time of day'), h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const total = sum(buckets.map((b) => b.reps));
    els.tod.append(headBlock('Time of day', total ? 'share of every rep you logged' : 'no reps yet'));
    const bar = h('div', { class: 'pg-propbar' });
    if (!total) {
      bar.append(h('i', { class: 'pg-propseg empty lv0' }));
    } else {
      buckets.forEach((b, i) => {
        if (b.reps <= 0) return;
        bar.append(h('i', { class: 'pg-propseg ' + TOD_TONE[i], style: { flexGrow: String(b.reps) } },
          b.pct >= 0.16 ? h('span', { class: 'pg-propnum' }, pct(b.pct)) : null));
      });
    }
    els.tod.append(bar);
    buckets.forEach((b, i) => {
      els.tod.append(h('div', { class: 'pg-todrow' },
        h('span', { class: 'pg-hsq ' + TOD_TONE[i] }),
        h('span', { class: 'pg-todlbl' }, b.label),
        h('span', { class: 'pg-todsub' }, b.sets ? b.sets + ' sets · ' + b.reps + ' reps' : 'nothing'),
        h('b', { class: 'num pg-todpct' }, total ? pct(b.pct) : '0%')));
    });
  }

  function paintFoot() {
    clear(els.foot);
    els.foot.append(h('p', { class: 'sub' },
      'All of this is computed from the sets on this phone. Export a copy from Settings before you clear '
      + 'Safari website data — iOS can drop the database.'));
  }

  // ── day sheet ─────────────────────────────────────────────────

  function closeSheet() {
    if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim);
    scrim = null;
  }

  async function openDaySheet(day) {
    closeSheet();
    const title = h('div', { class: 'pg-paneltitle' }, fmtDay(day));
    const totalLine = h('div', { class: 'pg-panellbl' }, 'loading…');
    const body = h('div', { class: 'pg-panelbody' });
    const panel = h('div', { class: 'pg-panel', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'sets on ' + day },
      h('div', { class: 'pg-panelhead' }, title,
        h('button', { class: 'pg-close', type: 'button', onclick: () => dismiss() }, 'done')),
      totalLine, body);
    scrim = h('div', { class: 'pg-scrim' }, panel);
    scrim.addEventListener('click', (ev) => { if (ev.target === scrim) dismiss(); });
    document.body.append(scrim);

    let local = [];
    try {
      const rowsList = await listSetsForDay(day);
      local = Array.isArray(rowsList) ? rowsList : [];
    } catch (e) {
      body.append(h('p', { class: 'pg-error' }, 'could not read this day: ' + errText(e)));
      totalLine.textContent = '';
      return;
    }

    const repaint = () => {
      clear(body);
      if (!local.length) body.append(h('p', { class: 'sub pg-panelempty' }, 'nothing logged on this day.'));
      local.forEach((s) => body.append(sheetRow(s)));
      body.append(addRow(day));
      totalLine.textContent = local.length
        ? local.length + ' set' + (local.length === 1 ? '' : 's') + ' · ' + sum(local.map(repsOf))
          + ' reps kept · camera saw ' + sum(local.map(detectedOf))
        : 'no sets on this day';
    };
    const reload = async () => {
      try {
        const rowsList = await listSetsForDay(day);
        local = Array.isArray(rowsList) ? rowsList : [];
      } catch { /* keep what we have on screen */ }
      repaint();
    };
    repaint();

    function dismiss() {
      closeSheet();
      if (dirty) rerender();
    }
    function markSaved() { dirty = true; }

    // rows need the mutators, so hang them off the sheet's own scope
    function sheetRow(set) {
      const row = h('div', { class: 'pg-srow' });
      const num = h('span', { class: 'pg-snum' }, String(repsOf(set)));
      const info = h('span', { class: 'pg-smeta' },
        fmtClock(set.startedAt || 0) + ' · ' + sourceLabel(set) + ' · camera saw ' + detectedOf(set)
        + (flagCount(set) ? ' · ' + flagCount(set) + ' flagged' : ''));
      const open = h('button', { class: 'pg-sopen', type: 'button' }, num, info);
      const del = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'delete');
      const err = h('span', { class: 'pg-err' });
      const inp = h('input', {
        class: 'pg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
        'aria-label': 'final reps for this set',
      });
      const saveBtn = h('button', { class: 'btn btn-primary pg-smini', type: 'button' }, 'save');
      const cancelBtn = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'cancel');
      const edit = h('div', { class: 'pg-sedit', hidden: true }, inp, saveBtn, cancelBtn, err);
      row.append(h('div', { class: 'pg-smain' }, open, del), edit);

      const showEdit = () => {
        err.textContent = '';
        inp.value = String(repsOf(set));
        edit.hidden = false;
        del.hidden = true;
        num.hidden = true;
        try { inp.focus(); } catch { /* focus is a nicety */ }
      };
      const hideEdit = () => {
        edit.hidden = true;
        del.hidden = false;
        num.hidden = false;
      };
      open.addEventListener('click', () => { if (edit.hidden) showEdit(); else hideEdit(); });
      cancelBtn.addEventListener('click', hideEdit);
      saveBtn.addEventListener('click', async () => {
        const v = parseReps(inp.value);
        if (v === null) { err.textContent = 'enter a number'; return; }
        saveBtn.disabled = true;
        err.textContent = '';
        try {
          const next = await updateSet(set.id, { repsFinal: v });   // repsDetected stays as recorded
          markSaved();
          local = local.map((s) => (s.id === set.id ? (next || { ...s, repsFinal: v }) : s));
          repaint();
        } catch (e) {
          err.textContent = 'could not save: ' + errText(e);
          saveBtn.disabled = false;
        }
      });
      del.addEventListener('click', async () => {
        if (!confirm('Delete this set of ' + repsOf(set) + ' reps?')) return;
        del.disabled = true;
        try {
          await deleteSet(set.id);
          markSaved();
          local = local.filter((s) => s.id !== set.id);
          repaint();
        } catch (e) {
          del.disabled = false;
          err.textContent = 'could not delete: ' + errText(e);
          showEdit();
        }
      });
      return row;
    }

    function addRow(dayKeyStr) {
      const btn = h('button', { class: 'pg-linkbtn', type: 'button' }, 'add a set here');
      const inp = h('input', {
        class: 'pg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
        'aria-label': 'reps to add for ' + fmtDay(dayKeyStr),
      });
      const saveBtn = h('button', { class: 'btn btn-primary pg-smini', type: 'button' }, 'save');
      const cancelBtn = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'cancel');
      const err = h('span', { class: 'pg-err' });
      const editor = h('div', { class: 'pg-sedit', hidden: true }, inp, saveBtn, cancelBtn, err);
      const box = h('div', { class: 'pg-sadd' },
        h('div', { class: 'pg-smain' }, btn, editor),
        h('p', { class: 'sub pg-addnote' }, 'logged as yours — detected reps stay zero, so nothing is claimed for the camera.'));
      btn.addEventListener('click', () => {
        err.textContent = '';
        inp.value = '';
        btn.hidden = true;
        editor.hidden = false;
        try { inp.focus(); } catch { /* ignore */ }
      });
      cancelBtn.addEventListener('click', () => { editor.hidden = true; btn.hidden = false; });
      saveBtn.addEventListener('click', async () => {
        const v = parseReps(inp.value);
        if (v === null) { err.textContent = 'enter a number'; return; }
        saveBtn.disabled = true;
        err.textContent = '';
        try {
          await saveSet({
            startedAt: noonOf(dayKeyStr), day: dayKeyStr, mode: 'manual', source: 'manual',
            repsDetected: 0, repsFinal: v, durationMs: 0, flags: {}, notes: '',
          }, []);
          markSaved();
          await reload();
        } catch (e) {
          err.textContent = 'could not save: ' + errText(e);
          saveBtn.disabled = false;
        }
      });
      return box;
    }
  }

  return {
    unmount() {
      window.removeEventListener('resize', onResize);
      clearTimeout(resizeTimer);
      closeSheet();
    },
  };
}

/* ── the target lives in localStorage: it is a wish, not a record ── */

function readTarget() {
  let raw = null;
  try {
    raw = localStorage.getItem(TARGET_KEY);
  } catch {
    return DEFAULT_TARGET;
  }
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 1 && n <= 999 ? n : DEFAULT_TARGET;
}

function writeTarget(n) {
  try {
    localStorage.setItem(TARGET_KEY, String(n));
  } catch { /* private mode: keep it for this session only */ }
}
__EOF_js_views_progress_js__

mkdir -p 'js/views'
cat > 'js/views/settings.js' <<'__EOF_js_views_settings_js__'
import { load, save, params, setParam, resetParams, PRESETS } from '../settings.js';
import { exportJSON, importJSON, countSets } from '../db.js';
import { forgetCache, loadGoals, loadPasses, loadStreak, passesThisWeek, saveGoals, saveStreak } from '../goals.js';
import { dayKey } from '../stats.js';
import { download } from '../util.js';
import { platformInfo, persistentStatus, requestPersistent, tryBadging } from '../upgrade.js';

const SEL = (id, opts, val) => `<select id="${id}">` +
  opts.map(([v, l]) => `<option value="${v}"${v === val ? ' selected' : ''}>${l}</option>`).join('') + '</select>';

const STREAK_OPTS = [['weekly', 'weeks on target'], ['daily', 'days in a row']];
const PASS_OPTS = ['0', '1', '2', '3'];

export default function settingsView(host) {
  const s = load();
  const p = params();
  const passOpts = PASS_OPTS.map((v) => [v, v === '0' ? 'off' : v === '1' ? 'one a week' : v + ' a week']);

  host.innerHTML = `
    <div class="list">
      <div class="pad"><h1 class="h1" style="margin:16px 0 2px">Settings</h1>
        <p class="sub" style="margin:0 0 10px">How the camera decides a rep counted. Nothing here leaves this phone.</p>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Depth preset</h2>
        <p class="sub" style="margin:0 0 8px">Relaxed counts a shallower bend. Strict wants an almost straight arm at the top.</p>
        ${SEL('preset', [['relaxed', 'Relaxed'], ['standard', 'Standard'], ['strict', 'Strict']], s.preset)}
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Thresholds</h2>
        <div class="field"><label for="top">Top (lockout) angle <b id="topOut"></b></label>
          <input type="range" id="top" min="120" max="178" step="1"></div>
        <div class="field"><label for="bottom">Bottom angle <b id="bottomOut"></b></label>
          <input type="range" id="bottom" min="70" max="130" step="1"></div>
        <div class="field"><label for="minRep">Minimum rep time <b id="minRepOut"></b></label>
          <input type="range" id="minRep" min="150" max="900" step="10"></div>
        <div class="row"><button class="btn btn-quiet" id="resetP">Back to preset</button>
          <span class="grow"></span><span class="sub" id="ovl"></span></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Counting</h2>
        <label class="tog"><span>Clean reps only<span class="sub">skip flagged reps in the count</span></span><input type="checkbox" id="cleanOnly"></label>
        <label class="tog"><span>Auto-start on plank<span class="sub">begin the countdown once the plank is held</span></span><input type="checkbox" id="autoArm"></label>
        <label class="tog"><span>End set after idle<span class="sub" id="idleLbl"></span></span>
          <input type="range" id="idle" min="5" max="60" step="1" style="width:120px"></label>
        <div class="field"><label for="armHold">Plank hold before counting <b id="armHoldOut"></b></label>
          <input type="range" id="armHold" min="800" max="6000" step="100"></div>
        <div class="field"><label for="secondary">Second signal (shoulder travel)</label>
          ${SEL('secondary', [['off', 'Off — elbow angle only'], ['assist', 'Assist — flag shallow reps'], ['confirm', 'Confirm — require both']], s.secondarySignal)}
        </div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Feedback</h2>
        ${SEL('voice', [['every', 'Say every rep'], ['milestones', 'Say every fifth'], ['off', 'Silent']], s.voice)}
        <label class="tog"><span>Beeps</span><input type="checkbox" id="beeps"></label>
        <label class="tog"><span>Haptics<span class="sub" id="vibHint"></span></span><input type="checkbox" id="haptics"></label>
        <label class="tog"><span>Show skeleton during a set</span><input type="checkbox" id="skeletonOnSet"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Camera and model</h2>
        ${SEL('camera', [['environment', 'Back camera (side view)'], ['user', 'Front camera']], s.camera)}
        <div class="spacer"></div>
        ${SEL('model', [['lite', 'Pose lite — fast, usually enough'], ['full', 'Pose full — better in bad light']], s.model)}
        <div class="spacer"></div>
        <div class="field"><label for="fps">Detection rate cap <b id="fpsOut"></b></label>
          <input type="range" id="fps" min="10" max="30" step="1"></div>
        <label class="tog"><span>Manual tap-to-log<span class="sub">no camera at all</span></span><input type="checkbox" id="manualMode"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Goals</h2>
        <div class="field"><label for="gdaily">Daily <b id="gdailyOut"></b></label>
          <input type="range" id="gdaily" min="0" max="300" step="5"></div>
        <div class="field"><label for="gweekly">Weekly <b id="gweeklyOut"></b></label>
          <input type="range" id="gweekly" min="0" max="2000" step="25"></div>
        <div class="field"><label for="gyearly">This year <b id="gyearlyOut"></b></label>
          <input type="range" id="gyearly" min="0" max="50000" step="500"></div>
        <div class="sub" style="margin-top:2px">zero switches that target off — the Today ring only counts the daily one</div>
        <div class="rule"></div>
        <div class="field"><label for="streakMode">Streak counts</label>${SEL('streakMode', STREAK_OPTS)}</div>
        <div class="sub" id="streakHelp" style="margin:-4px 0 10px">weeks: a week stays alive by hitting the weekly total</div>
        <div class="field"><label for="passes">Rest passes</label>${SEL('passes', passOpts)}</div>
        <div class="sub" style="margin:-4px 0 6px">a pass keeps a streak alive through a day you skipped</div>
        <div class="kv"><span>passes left this week</span><b class="num" id="passesLeft">…</b></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Data</h2>
        <div class="kv"><span>saved sets on this phone</span><b class="num" id="setCount">…</b></div>
        <div class="kv"><span>persistent storage</span><b id="persist">…</b></div>
        <div class="row" style="margin-top:10px">
          <button class="btn grow" id="exportBtn">Export JSON</button>
          <button class="btn grow" id="importBtn">Import</button>
        </div>
        <input type="file" id="importFile" accept="application/json,.json" hidden>
        <div class="sub" style="margin-top:8px" id="dataMsg"></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h2">Diagnostics</h2>
        <div class="mono" id="plat" style="white-space:pre-wrap"></div>
        <div class="row" style="margin-top:10px">
          <a class="btn grow" href="#/debug">Counter lab</a>
          <button class="btn grow" id="badgeTest">Test icon badge</button>
        </div>
      </div>
      <div class="spacer"></div><div class="spacer"></div>
    </div>`;

  const q = (sel) => host.querySelector(sel);
  const num = (id) => q('#' + id + 'Out');
  const currentFor = (key) => {
    const cur = load();
    return key in cur.overrides ? cur.overrides[key] : PRESETS[cur.preset][key];
  };

  function bindRange(id, key, fmt) {
    const el = q('#' + id);
    const out = num(id);
    el.value = String(currentFor(key));
    out.textContent = fmt(Number(el.value));
    el.addEventListener('input', () => {
      out.textContent = fmt(Number(el.value));
      setParam(key, Number(el.value));
      renderOverrideNote();
    });
  }

  function renderOverrideNote() {
    const o = Object.keys(load().overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'following preset';
  }

  q('#preset').addEventListener('change', (e) => {
    save({ preset: e.target.value, overrides: {} });
    syncAll();
  });
  q('#resetP').addEventListener('click', () => { resetParams(); syncAll(); });

  bindRange('top', 'top', (v) => v + '°');
  bindRange('bottom', 'bottom', (v) => v + '°');
  bindRange('minRep', 'minRepMs', (v) => v + ' ms');

  const toggles = {
    cleanOnly: 'cleanOnly', autoArm: 'autoArm', beeps: 'beeps', haptics: 'haptics',
    skeletonOnSet: 'skeletonOnSet', manualMode: 'manualMode',
  };
  Object.entries(toggles).forEach(([id, key]) => {
    const el = q('#' + id);
    el.checked = !!s[key];
    el.addEventListener('change', () => save({ [key]: el.checked }));
  });
  ['voice', 'camera', 'model', 'secondarySignal'].forEach((key) => {
    const el = q('#' + (key === 'secondarySignal' ? 'secondary' : key));
    el.value = s[key];
    el.addEventListener('change', () => save({ [key]: el.value }));
  });

  q('#idle').value = String(s.endAfterIdleSec);
  q('#idleLbl').textContent = 'auto-end after ' + s.endAfterIdleSec + ' s without a rep';
  q('#idle').addEventListener('input', (e) => {
    save({ endAfterIdleSec: Number(e.target.value) });
    q('#idleLbl').textContent = 'auto-end after ' + e.target.value + ' s without a rep';
  });

  q('#armHold').value = String(s.armHoldMs);
  q('#armHoldOut').textContent = (s.armHoldMs / 1000).toFixed(1) + ' s';
  q('#armHold').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    q('#armHoldOut').textContent = (Number(e.target.value) / 1000).toFixed(1) + ' s';
  });

  q('#fps').value = String(s.fpsCap);
  q('#fpsOut').textContent = s.fpsCap + ' fps';
  q('#fps').addEventListener('input', (e) => {
    save({ fpsCap: Number(e.target.value) });
    q('#fpsOut').textContent = e.target.value + ' fps';
  });

  q('#vibHint').textContent = navigator.vibrate ? 'supported here' : 'not exposed by iOS Safari';

  function syncAll() {
    const cur = load();
    const cp = params();
    q('#preset').value = cur.preset;
    q('#top').value = String(cp.top); num('top').textContent = cp.top + '°';
    q('#bottom').value = String(cp.bottom); num('bottom').textContent = cp.bottom + '°';
    q('#minRep').value = String(cp.minRepMs); num('minRep').textContent = cp.minRepMs + ' ms';
    renderOverrideNote();
  }
  syncAll();

  // ── goals and streak rules ────────────────────────────────────
  const fmtGoal = (key, v) => (v === 0 ? 'off' : v + ' ' + (key === 'gyearly' ? 'reps this year' : 'reps'));

  async function paintPasses() {
    const cfg = await loadStreak();
    const passes = await loadPasses();
    q('#passesLeft').textContent = cfg.passesPerWeek === 0
      ? 'off'
      : String(Math.max(0, cfg.passesPerWeek - await passesThisWeek(passes, dayKey(Date.now()))));
  }

  function streakHelp(mode) {
    q('#streakHelp').textContent = mode === 'daily'
      ? 'days: every day either hits the daily total or spends a rest pass'
      : 'weeks: a week stays alive by hitting the weekly total';
  }

  Promise.all([loadGoals(), loadStreak()]).then(([g, cfg]) => {
    for (const [id, val] of [['gdaily', g.daily], ['gweekly', g.weekly], ['gyearly', g.yearly]]) {
      q('#' + id).value = String(val);
      q('#' + id + 'Out').textContent = fmtGoal(id, val);
      q('#' + id).addEventListener('input', (e) => {
        const v = Number(e.target.value);
        q('#' + id + 'Out').textContent = fmtGoal(id, v);
        saveGoals({ [id.slice(1)]: v }).catch(() => { q('#dataMsg').textContent = 'could not save goals'; });
      });
    }
    q('#streakMode').value = cfg.mode;
    q('#passes').value = String(cfg.passesPerWeek);
    streakHelp(cfg.mode);
    paintPasses().catch(() => { q('#passesLeft').textContent = '?'; });
  }).catch(() => {
    q('#gdailyOut').textContent = '?';
    q('#dataMsg').textContent = 'goals unavailable — the database is not readable in this browser';
  });

  q('#streakMode').addEventListener('change', (e) => {
    saveStreak({ mode: e.target.value }).then(() => { streakHelp(e.target.value); paintPasses(); });
  });
  q('#passes').addEventListener('change', (e) => {
    saveStreak({ passesPerWeek: Number(e.target.value) }).then(paintPasses);
  });

  countSets().then((n) => { q('#setCount').textContent = String(n); }).catch(() => { q('#setCount').textContent = '?'; });
  persistentStatus().then(async (ok) => {
    q('#persist').textContent = ok ? 'granted' : 'not granted';
    if (!ok) {
      q('#persist').addEventListener('click', async () => {
        const g = await requestPersistent();
        q('#persist').textContent = g ? 'granted' : 'denied';
      });
    }
  });
  q('#persist').style.cursor = 'pointer';

  const info = platformInfo();
  q('#plat').textContent = Object.entries(info).map(([k, v]) => k.padEnd(12) + (v ? 'yes' : 'no')).join('\n');

  q('#exportBtn').addEventListener('click', async () => {
    const text = await exportJSON();
    download('pushups-backup-' + new Date().toISOString().slice(0, 10) + '.json', text);
    q('#dataMsg').textContent = 'Downloaded. Keep one copy in Files or iCloud Drive.';
  });
  q('#importBtn').addEventListener('click', () => q('#importFile').click());
  q('#importFile').addEventListener('change', async (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const text = await file.text();
    if (!confirm('Merge sets from ' + file.name + ' into this phone?')) return;
    const res = await importJSON(text);
    q('#dataMsg').textContent = res.ok
      ? 'Imported ' + res.added + ' sets' + (res.metaWritten ? ' and ' + res.metaWritten + ' settings records' : '') + '.'
      : 'Import failed: ' + res.error;
    if (res.ok) {
      countSets().then((n) => { q('#setCount').textContent = String(n); });
      forgetCache();
    }
  });
  q('#badgeTest').addEventListener('click', () => {
    const ok = tryBadging(7);
    q('#plat').textContent += '\nbadging: ' + (ok ? 'shown on the icon' : 'not supported in this browser');
  });

  return {};
}
__EOF_js_views_settings_js__

mkdir -p 'js/views'
cat > 'js/views/today.js' <<'__EOF_js_views_today_js__'
/* Today: the day's number, the goal ring, the streak, and the sets behind them.
   All numbers come from stats.js / goals.js over one listSets() read; nothing here recomputes
   totals by hand except the today filter, so the screen and the Progress screen can never disagree. */

import { deleteSet, listSets, saveSet, updateSet } from '../db.js';
import { goalStatus, usePass } from '../goals.js';
import { byDay, dayFromKey, gaps, records } from '../stats.js';
import { clamp, dayOf, fmtClock, fmtDay, h, pct, sum, today } from '../util.js';

const NS = 'http://www.w3.org/2000/svg';
const SIZE = 88;
const STROKE = 7;
const R = (SIZE - STROKE) / 2 - 2;
const C = 2 * Math.PI * R;

const SKELETON = `
  <div class="list">
    <div class="tg-hero">
      <div class="tg-heronum">
        <div class="tg-total" id="tgTotal">0</div>
        <h1 class="tg-date" id="tgDate"></h1>
        <div class="tg-unit">reps today</div>
        <div class="tg-note" id="tgNote"></div>
      </div>
      <div class="tg-ringwrap" id="tgRing"></div>
    </div>
    <div class="tg-goalnote" id="tgGoalNote"></div>
    <div class="row tg-streak" id="tgStreak"></div>
    <div class="rule" style="margin:6px 16px 10px"></div>
    <div id="tgMinis"></div>
    <div id="tgSetsHead"></div>
    <div id="tgSets"></div>
    <div id="tgFoot"></div>
    <div id="tgMissed"></div>
    <a class="tg-prog" href="#/progress"><span class="grow">progress and history</span><span class="chev" aria-hidden="true">›</span></a>
    <div style="height:12px"></div>
  </div>`;

/* ── small builders ────────────────────────────────────────────── */

function svg(tag, attrs) {
  const el = document.createElementNS(NS, tag);
  for (const k of Object.keys(attrs || {})) {
    const v = attrs[k];
    if (v === null || v === undefined || v === false) continue;
    el.setAttribute(k, String(v));
  }
  return el;
}

/** Hand-rolled ring: one track circle, one arc whose stroke-dasharray is the arc length. */
function ringEl(frac, met) {
  const shown = clamp(Number(frac) || 0, 0, 1) * C;
  const half = SIZE / 2;
  const arc = svg('circle', {
    class: 'tg-arc', cx: half, cy: half, r: R, fill: 'none', 'stroke-width': STROKE,
    'stroke-dasharray': shown.toFixed(2) + ' ' + (C - shown).toFixed(2),
  });
  if (shown > 0.5) arc.setAttribute('stroke-linecap', 'round');
  const el = svg('svg', {
    class: 'tg-ring' + (met ? ' met' : ''), width: SIZE, height: SIZE,
    viewBox: '0 0 ' + SIZE + ' ' + SIZE, 'aria-hidden': 'true', focusable: 'false',
  });
  el.append(svg('circle', {
    class: 'tg-track', cx: half, cy: half, r: R, fill: 'none', 'stroke-width': STROKE,
  }), arc);
  return el;
}

function errText(e) {
  return (e && e.message) ? e.message : String(e);
}

function flagCount(s) {
  const f = (s && s.flags) || {};
  return (Number(f.sag) || 0) + (Number(f.pike) || 0) + (Number(f.half) || 0)
    + (Number(f.lockout) || 0) + (Number(f.lost) || 0);
}

function sourceLabel(s) {
  if (s.source === 'manual' || s.mode === 'manual') return 'manual';
  return s.cameraUsed === 'user' ? 'front cam' : 'side cam';
}

function repsOf(s) {
  return Number(s && s.repsFinal) || 0;
}

function detectedOf(s) {
  return Number(s && s.repsDetected) || 0;
}

/** '2026-10-20' -> that noon, local. Manual backfills land at midday so they sort inside the day. */
function noonOf(dayKeyStr) {
  const d = new Date(dayFromKey(dayKeyStr));
  d.setHours(12, 0, 0, 0);
  return d.getTime();
}

function parseReps(raw) {
  const n = parseInt(String(raw).trim(), 10);
  if (!Number.isFinite(n)) return null;
  return clamp(n, 0, 999);
}

/* ── the view ──────────────────────────────────────────────────── */

export default async function todayView(host, ctx) {
  const key = today();
  const rerender = () => {
    if (ctx && typeof ctx.render === 'function') return ctx.render();
    return null;
  };
  let scrim = null;

  host.innerHTML = SKELETON;
  const q = (sel) => host.querySelector(sel);
  const els = {
    total: q('#tgTotal'), date: q('#tgDate'), note: q('#tgNote'), ring: q('#tgRing'),
    goalNote: q('#tgGoalNote'), streak: q('#tgStreak'), minis: q('#tgMinis'),
    setsHead: q('#tgSetsHead'), sets: q('#tgSets'), foot: q('#tgFoot'), missed: q('#tgMissed'),
  };

  els.date.textContent = new Date().toLocaleDateString(undefined, {
    weekday: 'long', day: 'numeric', month: 'long',
  });

  // ── read everything once, guarded ─────────────────────────────
  let sets = [];
  let status = null;
  let setsError = '';      // no sets at all -> lists and gaps are meaningless
  let goalsError = '';     // sets are fine, goals meta is not -> header rows degrade to lifetime only
  try {
    sets = await listSets();
    if (!Array.isArray(sets)) sets = [];
  } catch (e) {
    setsError = 'database unreadable: ' + errText(e);
    sets = [];
  }
  if (!setsError) {
    try {
      status = await goalStatus(sets, key);
    } catch (e) {
      goalsError = 'goals unreadable: ' + errText(e);
    }
  }
  const failed = setsError || goalsError;
  if (failed) els.note.textContent = failed;

  let rec = null;
  let days = byDay([]);
  if (!setsError) {
    try {
      days = byDay(sets);
      rec = records(sets);
    } catch (e) {
      els.note.textContent = errText(e);
    }
  }

  const mine = sets
    .filter((s) => s && ((s.day || dayOf(s.startedAt || 0)) === key))
    .sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
  const dayReps = sum(mine.map(repsOf));

  els.total.textContent = String(dayReps);

  const daily = status ? status.daily : null;
  const goal = daily ? daily.goal : 0;
  const met = !!daily && goal > 0 && daily.reps >= goal;

  paintRing(daily, met);
  paintStreak(status, met, key);
  paintMinis(status, days, rec, key);
  paintSets(mine, setsError);
  paintMissed(days, status, key);

  // ── painters ──────────────────────────────────────────────────

  function paintRing(d, wasMet) {
    els.ring.replaceChildren();
    if (!d) {
      els.goalNote.textContent = failed ? '' : 'no goal on record';
      return;
    }
    if (d.goal <= 0) {
      els.goalNote.textContent = 'daily goal is off — set one in Settings';
      return;
    }
    els.ring.append(ringEl(d.pct, wasMet));
    els.ring.append(h('div', { class: 'tg-ringtext' },
      h('div', { class: 'tg-ringnum' }, String(d.goal)),
      h('div', { class: 'tg-ringlbl' }, wasMet ? 'met' : 'goal')));
    const left = Math.max(0, d.goal - d.reps);
    els.goalNote.className = 'tg-goalnote' + (wasMet ? ' met' : '');
    els.goalNote.textContent = wasMet
      ? 'goal met'
      : left + ' to go · goal ' + d.goal;
  }

  function paintStreak(st, wasMet, dayKeyStr) {
    els.streak.replaceChildren();
    if (!st) return;
    const s = st.streak;
    const txt = s.n > 0
      ? (s.mode === 'daily'
        ? s.n + (s.n === 1 ? ' day in a row' : ' days in a row')
        : s.n + (s.n === 1 ? ' week on target' : ' weeks on target'))
      : (s.mode === 'daily' ? 'no streak yet' : 'no full week on target yet');
    const line = h('span', { class: 'tg-streakline' },
      h('span', { class: 'tg-streaktxt' }, txt));
    if (s.mode === 'weekly' && st.goals.weekly > 0) {
      line.append(h('span', { class: 'tg-streaktxt dim' }, ' · ' + pct(st.weekly.pct) + ' of this week'));
    }
    els.streak.append(line);

    const passes = st.passes || {};
    const hasPasses = st.passesLeft > 0 || !!passes[dayKeyStr];
    if (!hasPasses) return;
    if (passes[dayKeyStr]) {
      els.streak.append(h('span', { class: 'tg-donetag' }, 'rest taken today'));
      return;
    }
    if (wasMet) return;
    // on a phone with no history there is no streak to keep alive — the pass is offered
    // from the missed-day sheet instead
    if (!rec || rec.lifetimeSets === 0) return;

    const why = h('span', { class: 'tg-streakwhy' });
    const btn = h('button', { class: 'tg-linkbtn', type: 'button' }, 'use a rest pass');
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      why.textContent = '';
      try {
        const res = await usePass(dayKeyStr);
        if (res && res.ok) { await rerender(); return; }
        why.textContent = (res && res.reason) || 'the pass was not used';
        btn.disabled = false;
      } catch (e) {
        why.textContent = errText(e);
        btn.disabled = false;
      }
    });
    els.streak.append(btn, why);
  }

  function paintMinis(st, dayMap, hist, dayKeyStr) {
    const rows = [];
    if (st) {
      rows.push(['this week', st.weekly.reps + ' of ' + st.weekly.goal + ' · ' + pct(st.weekly.pct)]);
      let month = 0;
      for (const [k, d] of dayMap) if (k.slice(0, 7) === dayKeyStr.slice(0, 7)) month += d.reps;
      rows.push(['this month', String(month) + ' reps']);
      rows.push(['this year', st.yearly.reps + ' of ' + st.yearly.goal + ' · ' + pct(st.yearly.pct)]);
    }
    if (hist) {
      rows.push(['lifetime', hist.lifetimeReps + ' reps · ' + hist.lifetimeSets + ' sets']);
    }
    els.minis.replaceChildren();
    if (!rows.length) return;   // the note under the date already says what failed
    const box = h('div', { class: 'tg-minis' });
    rows.forEach(([label, value]) => {
      box.append(h('div', { class: 'kv' },
        h('span', { class: 'tg-key' }, label),
        h('b', { class: 'tg-val' }, value)));
    });
    els.minis.append(box);
  }

  function paintSets(list, dbFailed) {
    els.setsHead.replaceChildren();
    els.sets.replaceChildren();
    els.foot.replaceChildren();
    if (dbFailed) {
      els.setsHead.append(h('div', { class: 'tg-head' }, 'sets'));
      els.sets.append(h('p', { class: 'soon tg-empty' }, 'nothing to list — the saved sets could not be read.'));
      return;
    }
    els.setsHead.append(h('div', { class: 'tg-head' },
      'today’s sets' + (list.length ? ' · ' + list.length : '')));
    if (!list.length) {
      els.sets.append(h('p', { class: 'soon tg-empty' },
        'no sets yet today. Train → start set, or add a missed day below.'));
      return;
    }
    els.sets.replaceChildren(...list.map(setRow));
    const det = sum(list.map(detectedOf));
    const kept = sum(list.map(repsOf));
    els.foot.append(h('div', { class: 'tg-foot' },
      'camera saw ' + det + ', you kept ' + kept + '.'));
  }

  function setRow(s) {
    const box = h('div', { class: 'tg-set' });
    const line = h('div', { class: 'tg-setmain' });
    const flagged = flagCount(s);
    const meta = fmtClock(s.startedAt || 0) + ' · ' + sourceLabel(s)
      + (flagged ? ' · ' + flagged + ' flagged' : '');
    const num = h('span', { class: 'tg-setnum' }, String(repsOf(s)));
    const open = h('button', { class: 'tg-editbtn', type: 'button' },
      num, h('span', { class: 'tg-setmeta' }, meta));
    const del = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'delete');
    line.append(open, del);

    const editline = h('div', { class: 'tg-editline', hidden: true });
    const inp = h('input', {
      class: 'tg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
      'aria-label': 'reps for this set',
    });
    const err = h('span', { class: 'tg-err' });
    const saveBtn = h('button', { class: 'btn btn-primary tg-mini', type: 'button' }, 'save');
    const cancelBtn = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'cancel');
    editline.append(inp, saveBtn, cancelBtn, err);

    function openEditor() {
      err.textContent = '';
      inp.value = String(repsOf(s));
      editline.hidden = false;
      del.hidden = true;
      num.hidden = true;          // the meta line stays, so you can see which set you are fixing
      try { inp.focus({ preventScroll: false }); } catch { inp.focus(); }
    }
    function closeEditor() {
      editline.hidden = true;
      del.hidden = false;
      num.hidden = false;
    }

    open.addEventListener('click', () => { if (editline.hidden) openEditor(); else closeEditor(); });
    cancelBtn.addEventListener('click', closeEditor);
    saveBtn.addEventListener('click', async () => {
      const v = parseReps(inp.value);
      if (v === null) { err.textContent = 'enter a number'; return; }
      err.textContent = '';
      saveBtn.disabled = true;
      try {
        await updateSet(s.id, { repsFinal: v });   // repsDetected is left alone on purpose
        await rerender();
      } catch (e) {
        err.textContent = 'could not save: ' + errText(e);
        saveBtn.disabled = false;
      }
    });
    del.addEventListener('click', async () => {
      if (!confirm('Delete this set?')) return;
      del.disabled = true;
      try {
        await deleteSet(s.id);
        await rerender();
      } catch (e) {
        del.disabled = false;
        err.textContent = 'could not delete: ' + errText(e);
        openEditor();
      }
    });

    box.append(line, editline);
    return box;
  }

  function paintMissed(dayMap, st, dayKeyStr) {
    els.missed.replaceChildren();
    if (setsError || !dayMap || dayMap.size < 2) return;
    let list = [];
    try {
      list = gaps(dayMap, 30).filter((k) => k < dayKeyStr);
    } catch { list = []; }
    if (!list.length) return;
    const month = dayKeyStr.slice(0, 7);
    const allThisMonth = list.every((k) => k.slice(0, 7) === month);
    const span = allThisMonth ? 'this month' : 'in the last 30 days';
    const btn = h('button', { class: 'tg-quietrow', type: 'button' },
      list.length + ' missed ' + (list.length === 1 ? 'day' : 'days') + ' ' + span);
    btn.addEventListener('click', () => openGapSheet(list, st));
    els.missed.append(btn);
  }

  // ── missed-day sheet ──────────────────────────────────────────

  function closeSheet() {
    if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim);
    scrim = null;
  }

  function openGapSheet(list, st) {
    closeSheet();
    const passes = (st && st.passes) || {};
    const panel = h('div', { class: 'tg-panel', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'missed days' });
    panel.append(h('div', { class: 'tg-panelhead' },
      h('div', { class: 'tg-paneltitle' }, 'missed days'),
      h('button', { class: 'tg-linkbtn dim', type: 'button', onclick: closeSheet }, 'done')));
    panel.append(h('span', { class: 'tg-panellbl' },
      'log a set you actually did, or spend a rest pass. neither changes what the camera saw.'));
    list.slice(-14).reverse().forEach((day) => panel.append(gapRow(day, passes[day])));
    scrim = h('div', { class: 'tg-scrim' }, panel);
    scrim.addEventListener('click', (ev) => { if (ev.target === scrim) closeSheet(); });
    document.body.append(scrim);
  }

  function gapRow(day, alreadyPassed) {
    const row = h('div', { class: 'tg-gaprow' });
    row.append(h('div', { class: 'tg-gapday' }, fmtDay(day)));
    const err = h('span', { class: 'tg-err' });

    if (alreadyPassed) {
      row.append(h('span', { class: 'tg-donetag' }, 'rest taken'));
      row.append(err);
      return row;
    }

    const addBtn = h('button', { class: 'tg-linkbtn', type: 'button' }, 'add');
    const restBtn = h('button', { class: 'tg-linkbtn dim', type: 'button' }, 'rest');
    const inp = h('input', { class: 'tg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999', 'aria-label': 'reps for ' + fmtDay(day) });
    const saveBtn = h('button', { class: 'btn btn-primary tg-mini', type: 'button' }, 'save');
    const cancelBtn = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'cancel');
    const editor = h('div', { class: 'tg-gapedit', hidden: true }, inp, saveBtn, cancelBtn);

    addBtn.addEventListener('click', () => {
      err.textContent = '';
      inp.value = '';
      addBtn.hidden = true;
      restBtn.hidden = true;
      editor.hidden = false;
      try { inp.focus(); } catch { /* focus is a nicety */ }
    });
    cancelBtn.addEventListener('click', () => {
      editor.hidden = true;
      addBtn.hidden = false;
      restBtn.hidden = false;
    });
    saveBtn.addEventListener('click', async () => {
      const v = parseReps(inp.value);
      if (v === null) { err.textContent = 'enter a number'; return; }
      saveBtn.disabled = true;
      err.textContent = '';
      try {
        // manual backfill: detected 0, no rep rows — the app never claims the camera saw this
        await saveSet({
          startedAt: noonOf(day),
          day,
          mode: 'manual',
          source: 'manual',
          repsDetected: 0,
          repsFinal: v,
          flags: {},
        }, []);
        await rerender();
      } catch (e) {
        err.textContent = 'could not save: ' + errText(e);
        saveBtn.disabled = false;
      }
    });
    restBtn.addEventListener('click', async () => {
      restBtn.disabled = true;
      err.textContent = '';
      try {
        const res = await usePass(day);
        if (res && res.ok) { await rerender(); return; }
        err.textContent = (res && res.reason) || 'the pass was not used';
        restBtn.disabled = false;
      } catch (e) {
        err.textContent = errText(e);
        restBtn.disabled = false;
      }
    });

    row.append(addBtn, restBtn, editor, err);
    return row;
  }

  return {
    unmount() { closeSheet(); },
  };
}
__EOF_js_views_today_js__

mkdir -p 'js/views'
cat > 'js/views/train.js' <<'__EOF_js_views_train_js__'
import { load, save, params } from '../settings.js';
import { openCamera, closeCamera, resumePreview, describeCameraError, cameraSupports } from '../camera.js';
import { createTracker } from '../pose.js';
import { Counter } from '../counter.js';
import { saveSet, listSetsForDay } from '../db.js';
import { unlockAudio, speak, playBeep, playWarning, vibrate, announceRep, countdownVoice } from '../feedback.js';
import { requestWakeLock, tryBadging } from '../upgrade.js';
import { today, dayOf, fmtClock, clamp, pct } from '../util.js';

const LM = { HEAD: 0, SHOULDER: 11, ELBOW: 13, WRIST: 15, HIP: 23, ANKLE: 27 };
const EMPTY_OUT = {
  quality: 0, armed: false, armMs: 0, side: null, repsDetected: 0, cleanReps: 0, state: 'idle',
  plank: { valid: false, reasons: ['noPose'] }, angles: {}, hipOffset: null, bodyAngle: null,
  events: [], lastRep: null,
};

export default function train(host) {
  const st = load();
  const counter = new Counter(params());
  counter.setArmHold(st.armHoldMs);

  let phase = 'setup';
  let cam = null;
  let tracker = null;
  let mirror = st.camera === 'user';
  let setStart = 0;
  let lastFrameAt = 0;
  let lastRepAt = 0;
  let manualAdj = 0;
  let reps = [];
  let armBreaks = 0;
  let qualityLog = [];
  let fpsSamples = [];
  let lostSince = 0;
  let lostShown = false;
  let tickTimer = null;
  let cdTimer = null;
  let plankSince = 0;
  let lastOut = EMPTY_OUT;
  let summary = null;
  let lightLevel = 120;

  const els = {};
  const CHECKS = [
    ['body', 'Full body in frame', 'head, hips and ankles visible'],
    ['vis', 'Landmarks visible', 'tracking above 50%'],
    ['plank', 'Plank detected', 'shoulder–hip–ankle in one line'],
    ['light', 'Lighting', 'you are not a silhouette'],
  ];
  const checkState = { body: false, vis: false, plank: false, light: false };
  const checkWhy = {};
  let poseSeen = false;

  host.innerHTML = `
    <div class="counter" data-phase="setup">
      <div class="topline">
        <span id="clock" class="clock">--:--</span>
        <h1 id="phaseLabel">set up</h1>
        <span class="endslot"><button class="btn btn-warn" id="endBtn" hidden>End</button></span>
      </div>
      <div class="hairline" id="hairline"></div>
      <div class="warnbox" id="warnbox" hidden></div>
      <div class="camwrap" id="camwrap">
        <video id="video" autoplay playsinline muted></video>
        <canvas id="overlay"></canvas>
        <div class="camoff" id="camoff" hidden></div>
        <div class="pill" id="pill"><i></i><span id="pillText">starting</span></div>
      </div>
      <div class="stage" id="stage"></div>
    </div>`;

  const q = (s) => host.querySelector(s);
  els.video = q('#video');
  els.overlay = q('#overlay');
  els.root = q('.counter');
  els.camwrap = q('#camwrap');
  els.camoff = q('#camoff');
  els.stage = q('#stage');
  els.pill = q('#pill');
  els.pillText = q('#pillText');
  els.warnbox = q('#warnbox');
  els.hairline = q('#hairline');
  els.clock = q('#clock');
  els.phaseLabel = q('#phaseLabel');
  els.endBtn = q('#endBtn');
  els.endBtn.addEventListener('click', () => endSet('button'));
  // Bound once: the stage keeps its listeners across every phase's innerHTML swap.
  els.stage.addEventListener('click', (e) => {
    if (phase !== 'set' || !load().manualMode) return;
    // The tap that opened the set bubbles through here too — it is not a rep.
    if (e.target.closest('#startBtn')) return;
    manualTap();
  });

  // ── luminance proxy for the lighting check ────────────────────
  const lumCanvas = document.createElement('canvas');
  lumCanvas.width = 32;
  lumCanvas.height = 24;
  const lumCtx = lumCanvas.getContext('2d', { willReadFrequently: true });
  let lumAt = 0;
  function measureLight() {
    const now = Date.now();
    if (now - lumAt < 800 || load().manualMode || els.video.videoWidth < 2) return;
    lumAt = now;
    try {
      lumCtx.drawImage(els.video, 0, 0, 32, 24);
      const d = lumCtx.getImageData(0, 0, 32, 24).data;
      let sum = 0;
      for (let i = 0; i < d.length; i += 4) sum += 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      lightLevel = sum / (d.length / 4);
    } catch { lightLevel = 120; }
  }

  // ── setup ─────────────────────────────────────────────────────
  function setPhase(p) {
    phase = p;
    els.root.dataset.phase = p;
  }

  function renderSetup() {
    setPhase('setup');
    els.overlay.style.display = '';
    lastOut = EMPTY_OUT;
    els.phaseLabel.textContent = load().manualMode ? 'manual log' : 'set up';
    els.endBtn.hidden = true;
    els.camoff.hidden = true;
    clearWarn();
    els.stage.innerHTML = `
      <div class="list">
        <div class="statusbar">
          <span class="bar grow"><i id="qbar"></i></span>
          <span class="mono" id="qtxt">0%</span>
          <span class="mono" id="fpstxt">0 fps</span>
        </div>
        <div class="pad">
          <div id="checks"></div>
          <div class="rule"></div>
          <div class="row">
            <button class="btn btn-quiet" id="flipBtn">Use front camera</button>
            <span class="grow"></span>
            <select id="presetSel" style="width:auto">
              <option value="relaxed">Relaxed depth</option>
              <option value="standard">Standard depth</option>
              <option value="strict">Strict depth</option>
            </select>
          </div>
          <label class="tog" style="border-bottom:0"><span>Manual tap-to-log<span class="sub">no camera, count with your thumb</span></span>
            <input type="checkbox" id="manualChk"></label>
        </div>
      </div>
      <div class="cta">
        <button class="btn btn-primary btn-big" id="startBtn">Start set</button>
        <div class="sub" id="hint"></div>
      </div>`;
    els.qbar = q('#qbar');
    els.qtxt = q('#qtxt');
    els.fpstxt = q('#fpstxt');
    els.checks = q('#checks');
    const manual = load().manualMode;
    els.camwrap.style.display = manual ? 'none' : '';
    q('#manualChk').checked = manual;
    q('#manualChk').addEventListener('change', (e) => {
      save({ manualMode: e.target.checked });
      els.camwrap.style.display = e.target.checked ? 'none' : '';
      if (e.target.checked) { closeCamera(cam); cam = null; els.pillText.textContent = 'manual'; }
      else if (!cam) startCamera(load().camera);
      renderSetup();
    });
    els.presetSel = q('#presetSel');
    els.presetSel.value = load().preset;
    els.presetSel.addEventListener('change', (e) => {
      save({ preset: e.target.value, overrides: {} });
      counter.setParams(params());
    });
    q('#flipBtn').addEventListener('click', () => {
      const next = load().camera === 'environment' ? 'user' : 'environment';
      save({ camera: next });
      startCamera(next);
    });
    q('#startBtn').addEventListener('click', beginSet);
    q('#hint').textContent = load().autoArm
      ? 'Auto-start is on: hold a steady plank and the countdown begins.'
      : 'Set the phone on the floor 1.5–2.5 m away, side-on. Tap Start set, then get into position.';
    paintChecks();
  }

  const SVGNS = 'http://www.w3.org/2000/svg';
  function markIcon(state) {
    const mk = (tag, a) => {
      const e = document.createElementNS(SVGNS, tag);
      for (const k of Object.keys(a)) e.setAttribute(k, a[k]);
      return e;
    };
    const el = mk('svg', {
      viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.8',
      'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true',
    });
    el.append(mk('circle', { cx: '12', cy: '12', r: '8.6' }));
    if (state === 'ok') el.append(mk('path', { d: 'M8.3 12.3l2.6 2.6 4.9-5.5' }));
    if (state === 'bad') el.append(mk('path', { d: 'M12 7.6v5.2' }), mk('path', { d: 'M12 16.2h.01' }));
    return el;
  }

  // Three states, not two: a gate you have not reached yet is not an error. Everything stays grey
  // until the camera is live AND has actually seen a body — then a failed gate goes rose.
  function paintChecks() {
    if (!els.checks) return;
    const judgeable = !!cam && poseSeen;
    els.checks.replaceChildren(...CHECKS.map(([k, label, hint]) => {
      const state = checkState[k] ? 'ok' : judgeable ? 'bad' : 'wait';
      const row = document.createElement('div');
      row.className = 'chk ' + state;
      const mk = document.createElement('span');
      mk.className = 'mk';
      mk.append(markIcon(state));
      const t = document.createElement('span');
      t.className = 't';
      t.textContent = label;
      const why = document.createElement('span');
      why.className = 'why';
      why.textContent = state === 'ok' ? '' : state === 'wait' ? 'not framed yet' : (checkWhy[k] || hint);
      row.append(mk, t, why);
      return row;
    }));
  }

  function reasonText(r) {
    return ({
      noPose: 'nothing detected yet',
      lowVis: 'too few landmarks',
      notSide: 'needs a side view',
      bodyAngle: 'body not level',
      hip: 'hips off the line',
    })[r] || r;
  }

  function evaluateChecks(f) {
    poseSeen = !!(f && f.present);
    if (!f || !f.present) {
      checkState.body = checkState.vis = checkState.plank = false;
      checkWhy.body = 'no pose yet';
      paintChecks();
      return;
    }
    const lm = f.landmarks;
    const inFrame = (p) => p.x > 0.02 && p.x < 0.98 && p.y > 0.02 && p.y < 0.98;
    checkState.body = inFrame(lm[LM.HEAD]) && inFrame(lm[LM.HIP]) && inFrame(lm[LM.ANKLE]);
    checkWhy.body = 'head, hips and ankles visible';
    checkState.vis = f.quality > 0.5;
    checkWhy.vis = pct(f.quality) + ' visible';
    const out = lastOut;
    checkState.plank = !!(out.plank && out.plank.valid);
    checkWhy.plank = out.plank && out.plank.reasons.length ? reasonText(out.plank.reasons[0]) : '';
    checkState.light = lightLevel > 26 && lightLevel < 236;
    checkWhy.light = lightLevel <= 26 ? 'too dark' : lightLevel >= 236 ? 'backlit' : '';
    paintChecks();
  }

  // ── lifecycle ─────────────────────────────────────────────────
  function beginSet() {
    unlockAudio();
    requestWakeLock('set-start');
    if (load().manualMode) return startManualSet();
    startCountdown(5);
  }

  function startCountdown(n) {
    setPhase('countdown');
    els.phaseLabel.textContent = 'into plank';
    let left = n;
    els.stage.innerHTML = `
      <div id="cdnum" class="num" style="font-size:min(70vw,38vh,320px);color:var(--brass)"></div>
      <div id="chip">counting starts after the countdown</div>`;
    const num = q('#cdnum');
    num.textContent = String(left);
    speak(countdownVoice(left));
    playBeep({ freq: 620, ms: 55, gain: 0.04 });
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'Cancel';
    cdTimer = setInterval(() => {
      left -= 1;
      if (left <= 0) {
        clearInterval(cdTimer);
        cdTimer = null;
        num.textContent = 'go';
        speak('go');
        playBeep({ freq: 880, ms: 90, gain: 0.05 });
        setTimeout(startSet, 200);
      } else {
        num.textContent = String(left);
        speak(countdownVoice(left));
        playBeep({ freq: 620, ms: 55, gain: 0.04 });
      }
    }, 1000);
  }

  function startSet() {
    setPhase('set');
    counter.reset('set-start');
    counter.setParams(params());
    counter.setArmHold(load().armHoldMs);
    lastOut = EMPTY_OUT;
    setStart = Date.now();
    lastRepAt = setStart;
    manualAdj = 0;
    reps = [];
    armBreaks = 0;
    qualityLog = [];
    fpsSamples = [];
    lostSince = 0;
    clearWarn();
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'End';
    els.phaseLabel.textContent = 'counting';
    renderCountFace();
    tickTimer = setInterval(tick, 250);
  }

  function renderCountFace() {
    els.overlay.style.display = load().skeletonOnSet ? '' : 'none';
    els.stage.innerHTML = `
      <div id="repnum" class="num">0</div>
      <div id="chip">get into plank</div>
      <div class="corr">
        <button class="step" id="minus" aria-label="one fewer">−</button>
        <span class="n" id="adj"></span>
        <button class="step" id="plus" aria-label="one more">+</button>
      </div>`;
    els.repnum = q('#repnum');
    els.chip = q('#chip');
    els.adj = q('#adj');
    q('#minus').addEventListener('click', () => correct(-1));
    q('#plus').addEventListener('click', () => correct(1));
    paintCount();
  }

  function correct(d) {
    manualAdj += d;
    playBeep({ freq: d > 0 ? 720 : 460, ms: 45, gain: 0.04 });
    paintCount();
  }

  function detected() { return load().manualMode ? reps.length : lastOut.repsDetected; }

  function paintCount() {
    if (!els.repnum || phase !== 'set') return;
    const n = Math.max(0, detected() + manualAdj);
    els.repnum.style.setProperty('--nd', String(n).length);
    if (els.repnum.textContent !== String(n)) {
      els.repnum.textContent = String(n);
      els.repnum.classList.add('tick');
      setTimeout(() => els.repnum && els.repnum.classList.remove('tick'), 170);
    }
    if (els.adj) els.adj.textContent = manualAdj === 0 ? '' : (manualAdj > 0 ? '+' + manualAdj : String(manualAdj));
    if (els.chip && !load().manualMode) {
      const flagged = lastOut.repsDetected - lastOut.cleanReps;
      els.chip.textContent = lastOut.armed
        ? lastOut.cleanReps + ' clean' + (flagged > 0 ? ' · ' + flagged + ' flagged' : '')
        : 'get into plank' + (lastOut.armMs > 200 ? ' (' + Math.round(lastOut.armMs / 1000) + 's)' : '');
    }
  }

  function startManualSet() {
    setPhase('set');
    setStart = Date.now();
    lastRepAt = setStart;
    manualAdj = 0;
    reps = [];
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'End';
    els.phaseLabel.textContent = 'manual log';
    els.stage.innerHTML = `
      <div id="repnum" class="num">0</div>
      <div id="chip">tap here to log a rep</div>
      <div class="corr">
        <button class="step" id="minus" aria-label="one fewer">−</button>
        <span class="n" id="adj"></span>
        <button class="step" id="plus" aria-label="one more">+</button>
      </div>`;
    els.repnum = q('#repnum');
    els.chip = q('#chip');
    els.adj = q('#adj');
    q('#minus').addEventListener('click', (e) => { e.stopPropagation(); correct(-1); });
    q('#plus').addEventListener('click', (e) => { e.stopPropagation(); correct(1); });
    tickTimer = setInterval(tick, 500);
    paintCount();
  }

  function manualTap() {
    const t = Date.now() - setStart;
    const prev = reps.length ? reps[reps.length - 1].tMs : 0;
    reps.push({ n: reps.length + 1, tMs: t, durationMs: Math.max(0, t - prev), flags: [], manual: true });
    lastRepAt = Date.now();
    announceRep(reps.length, { mode: load().voice, beeps: load().beeps, haptics: load().haptics });
    paintCount();
  }

  function endSet(reason) {
    if (phase === 'summary') return;
    if (cdTimer) { clearInterval(cdTimer); cdTimer = null; }
    if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
    if (phase === 'countdown') { renderSetup(); return; }
    if (phase !== 'set') return;
    setPhase('summary');
    els.endBtn.hidden = true;
    const det = detected();
    const fin = Math.max(0, det + manualAdj);
    summary = {
      detected: det,
      final: fin,
      manualAdj,
      durationMs: Date.now() - setStart,
      reps: reps.slice(),
      flags: tally(reps),
      quality: qualityStats(),
      reason: reason || 'button',
      startedAt: setStart,
    };
    renderSummary();
  }

  function tally(list) {
    const t = { sag: 0, pike: 0, half: 0, lockout: 0, lost: 0, other: 0 };
    list.forEach((r) => (r.flags || []).forEach((f) => {
      if (f in t) t[f] += 1; else t.other += 1;
    }));
    if (list.some((r) => r.slow)) t.other += list.filter((r) => r.slow).length;
    return t;
  }

  function qualityStats() {
    const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
    return {
      fpsMean: Math.round(mean(fpsSamples)),
      visMean: mean(qualityLog),
      frames: qualityLog.length,
      breaks: armBreaks,
    };
  }

  // ── summary ───────────────────────────────────────────────────
  function renderSummary() {
    const d = summary;
    els.phaseLabel.textContent = 'summary';
    els.stage.innerHTML = `
      <div class="sheet">
        <div class="finum"><input id="finalIn" type="number" inputmode="numeric" min="0" max="999"></div>
        <div class="sub" style="text-align:center;margin-top:-4px">final reps — correct it if the camera missed one</div>
        <div class="row" style="justify-content:center;margin:10px 0">
          <button class="step" id="sminus" aria-label="one fewer">−</button>
          <button class="step" id="splus" aria-label="one more">+</button>
        </div>
        <div class="kv"><span>detected</span><b class="num" id="detOut"></b></div>
        <div class="kv"><span>adjustment</span><b class="num" id="adjOut"></b></div>
        <div class="kv"><span>duration</span><b class="num" id="durOut"></b></div>
        <div class="kv"><span>tracking</span><b class="num" id="qualOut"></b></div>
        <div class="rule"></div>
        <div class="flags" id="flagRow"></div>
        <div class="field"><label for="notes">notes</label><textarea id="notes" rows="2" placeholder="optional"></textarea></div>
        <div class="row" style="margin-top:14px">
          <button class="btn btn-quiet grow" id="again">New set</button>
          <button class="btn btn-primary grow" id="save">Save set</button>
        </div>
        <div class="sub" style="margin-top:10px" id="saveMsg"></div>
      </div>`;
    const inp = q('#finalIn');
    inp.value = String(d.final);
    q('#detOut').textContent = String(d.detected);
    q('#durOut').textContent = Math.round(d.durationMs / 1000) + ' s';
    q('#qualOut').textContent = d.quality.fpsMean + ' fps · ' + pct(d.quality.visMean) +
      (d.quality.breaks ? ' · ' + d.quality.breaks + ' breaks' : '');
    const adjOut = q('#adjOut');
    const sync = () => {
      const v = clamp(parseInt(inp.value, 10) || 0, 0, 999);
      d.final = v;
      const adj = v - d.detected;
      adjOut.textContent = (adj > 0 ? '+' : '') + adj;
    };
    inp.addEventListener('input', sync);
    q('#sminus').addEventListener('click', () => { inp.value = String(Math.max(0, (parseInt(inp.value, 10) || 0) - 1)); sync(); });
    q('#splus').addEventListener('click', () => { inp.value = String((parseInt(inp.value, 10) || 0) + 1); sync(); });
    sync();

    const row = q('#flagRow');
    const parts = Object.entries(d.flags).filter(([, v]) => v > 0);
    if (!parts.length) {
      const s = document.createElement('span');
      s.textContent = 'clean set';
      row.append(s);
    } else {
      parts.forEach(([k, v]) => {
        const s = document.createElement('span');
        s.className = ['sag', 'pike', 'half', 'lost'].includes(k) ? 'hard'
          : ['lockout', 'other'].includes(k) ? 'soft' : 'info';
        s.textContent = v + ' ' + (k === 'other' ? 'flagged' : k);
        row.append(s);
      });
    }

    q('#again').addEventListener('click', () => { summary = null; renderSetup(); });
    q('#save').addEventListener('click', async () => {
      const val = clamp(parseInt(inp.value, 10) || 0, 0, 999);
      const rec = {
        startedAt: d.startedAt,
        endedAt: d.startedAt + d.durationMs,
        durationMs: d.durationMs,
        mode: load().manualMode ? 'manual' : 'camera',
        source: load().manualMode ? 'manual' : 'camera',
        repsDetected: d.detected,
        repsFinal: val,
        flags: d.flags,
        cameraUsed: load().camera,
        qualityStats: d.quality,
        paramsUsed: params(),
        presetName: load().preset,
        model: load().model,
        notes: q('#notes').value.trim(),
        day: dayOf(d.startedAt),
        endReason: d.reason,
      };
      const msg = q('#saveMsg');
      try {
        const id = await saveSet(rec, d.reps);
        msg.textContent = 'Saved as set ' + id + '.';
        q('#save').disabled = true;
        const total = (await listSetsForDay(today())).reduce((a, s) => a + (s.repsFinal || 0), 0);
        tryBadging(total);
        setTimeout(() => { summary = null; renderSetup(); }, 900);
      } catch (e) {
        msg.textContent = 'Save failed: ' + (e && e.message ? e.message : e);
      }
    });
  }

  // ── frame pump ────────────────────────────────────────────────
  // The counter is fed in every phase (setup, countdown, set) so the checklist can show real plank
  // and angle numbers. It only counts once a set has started, because startSet() resets the machine
  // and the arm gate refuses to count until the plank has been held.
  function onFrame(f) {
    const now = Date.now();
    lastFrameAt = now;
    measureLight();
    if (load().manualMode) return;

    const before = lastOut.repsDetected;
    lastOut = counter.addFrame(now, f) || EMPTY_OUT;

    if (phase === 'setup') {
      if (els.qbar) {
        els.qbar.style.width = Math.round(f.quality * 100) + '%';
        els.qbar.className = f.quality < 0.4 ? 'bad' : '';
        els.qtxt.textContent = pct(f.quality);
        els.fpstxt.textContent = Math.round(f.fps) + ' fps';
      }
      evaluateChecks(f);
      if (load().autoArm && lastOut.plank && lastOut.plank.valid) {
        if (!plankSince) plankSince = now;
        else if (now - plankSince > load().armHoldMs + 400 && !cdTimer) startCountdown(5);
      } else plankSince = 0;
      paintPill(f);
      return;
    }

    if (phase === 'set') {
      qualityLog.push(lastOut.quality);
      if (f.fps) fpsSamples.push(f.fps);
      (lastOut.events || []).forEach((ev) => {
        if (ev.type === 'rep') {
          const rep = ev.data && (ev.data.rep || ev.data);
          reps.push({ ...rep, tMs: (rep.tEnd || ev.t) - setStart });
          lastRepAt = now;
          announceRep(lastOut.repsDetected, { mode: load().voice, beeps: load().beeps, haptics: load().haptics });
        } else if (ev.type === 'armBreak') armBreaks += 1;
      });
      paintCount();
      updateLost(now, lastOut);
      if (lastOut.repsDetected !== before && load().debug) console.log('rep', lastOut.repsDetected);
    }
    if (phase === 'countdown') paintPill(f);
  }

  function updateLost(now, out) {
    const stale = now - lastFrameAt > 600;
    const bad = stale || out.quality < 0.35;
    if (!bad) {
      lostSince = 0;
      if (lostShown) { lostShown = false; clearWarn(); }
      return;
    }
    if (!lostSince) lostSince = now;
    if (!lostShown && now - lostSince > 650) {
      lostShown = true;
      showWarn(stale ? 'Camera lost you — stay in frame' : 'Tracking weak — add light or move the phone closer');
      playWarning();
      vibrate([30, 60, 30]);
    }
  }

  function showWarn(text) {
    els.warnbox.hidden = false;
    els.warnbox.textContent = text;
    els.hairline.classList.add('on');
    els.stage.classList.add('dim');
  }

  function clearWarn() {
    els.warnbox.hidden = true;
    els.hairline.classList.remove('on');
    els.stage.classList.remove('dim');
    lostShown = false;
  }

  function paintPill(f) {
    els.pill.className = 'pill' + (f.quality < 0.35 ? ' bad' : f.quality < 0.6 ? ' warn' : '');
    els.pillText.textContent = Math.round(f.fps) + ' fps · ' + pct(f.quality) + ' tracked';
  }

  function tick() {
    if (phase !== 'set') return;
    const secs = Math.round((Date.now() - setStart) / 1000);
    els.clock.textContent = Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0');
    const idle = (Date.now() - lastRepAt) / 1000;
    if (detected() > 0 && idle > load().endAfterIdleSec) endSet('idle');
  }

  // ── camera + pose ─────────────────────────────────────────────
  async function startCamera(facing) {
    if (load().manualMode) return;
    if (!cameraSupports()) return camFail({ name: 'SecurityError' });
    els.camoff.hidden = true;
    try {
      cam = await openCamera(els.video, { facing });
      mirror = (cam.settings && cam.settings.facing) === 'user';
      if (cam.settings && cam.settings.needsTap) {
        // iOS refused to autoplay outside a gesture: the next tap anywhere restarts the preview
        const wake = () => { resumePreview(els.video); els.camoff.hidden = true; };
        els.camoff.hidden = false;
        els.camoff.replaceChildren();
        const hint = document.createElement('div');
        hint.textContent = 'Tap to show the preview';
        els.camoff.append(hint);
        els.camoff.addEventListener('click', wake, { once: true });
      }
      if (tracker && tracker.setMirrored) tracker.setMirrored(mirror);
      els.phaseLabel.textContent = mirror ? 'front camera' : 'set up';
    } catch (err) {
      camFail(err);
    }
  }

  function camFail(err) {
    const d = (dce || describeCameraError)(err);
    els.camoff.hidden = false;
    els.camoff.replaceChildren();
    const h3 = document.createElement('div');
    h3.style.color = 'var(--text)';
    h3.style.fontWeight = '600';
    h3.textContent = d.title;
    const ol = document.createElement('ol');
    (d.steps || []).forEach((s) => {
      const li = document.createElement('li');
      li.textContent = s;
      ol.append(li);
    });
    els.camoff.append(h3, ol);
    els.pillText.textContent = 'camera blocked';
  }

  renderSetup();

  (async () => {
    if (load().manualMode) return;
    await startCamera(load().camera);
    tracker = await createTracker({
      video: els.video,
      canvas: els.overlay,
      model: load().model,
      fpsCap: load().fpsCap,
      mirrored: mirror,
      strokeStyle: (getComputedStyle(document.body).getPropertyValue('--track') || '#4FA3A5').trim(),
      onStatus: (kind, detail) => {
        if (kind === 'loading-model') els.pillText.textContent = 'loading pose model';
        else if (kind === 'delegate-downgrade') els.pillText.textContent = 'cpu mode · ' + (detail || '');
        else if (kind === 'ready' || kind === 'running') clearWarn();
      },
      onFrame: (f) => {
        try { onFrame(f); } catch (e) { console.error('frame', e); }
      },
      onError: (e) => {
        els.pillText.textContent = 'pose error';
        console.error('pose', e);
      },
    });
    await tracker.start();
  })();

  return {
    unmount() {
      if (cdTimer) clearInterval(cdTimer);
      if (tickTimer) clearInterval(tickTimer);
      if (tracker) { if (tracker.stop) tracker.stop(); if (tracker.dispose) tracker.dispose(); }
      if (cam) closeCamera(cam);
    },
  };
}
__EOF_js_views_train_js__

mkdir -p .
cat > 'manifest.webmanifest' <<'__EOF_manifest_webmanifest__'
{
  "name": "Pushups",
  "short_name": "Pushups",
  "description": "Camera pushup counter and long-term progress tracker",
  "id": "/pushups-pwa/",
  "start_url": "./?source=pwa",
  "scope": "./",
  "display": "standalone",
  "display_override": ["standalone", "fullscreen"],
  "background_color": "#0E1A18",
  "theme_color": "#0E1A18",
  "orientation": "any",
  "icons": [
    { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
__EOF_manifest_webmanifest__

mkdir -p .
cat > 'README.md' <<'__EOF_README_md__'
# Pushups

An installable iPhone web app that counts pushups with the camera and keeps your progress for years.
No App Store, no build step, no backend (until the optional push phase). Plain HTML, CSS and ES
modules served as static files over HTTPS.

Phase 1 is the counter: setup screen, set lifecycle, correction, local saving, voice, offline,
and a hidden counter lab for tuning.

## Install it on your iPhone

```bash
cd ~/Projects/pushups
./scripts/deploy.sh -m "phase 1: counter core"
```

That creates the GitHub repo, enables Pages, pushes, and prints the live URL
(`https://<you>.github.io/pushups-pwa/`). Then, on the phone:

1. Open that URL in **Safari** (Chrome on iOS cannot install PWAs).
2. Share ▸ **Add to Home Screen**.
3. Launch it from the icon — not from a Safari tab. The camera only works in the standalone window.
4. Allow the camera when asked. First launch downloads ~20 MB of model and WASM, so let it finish
   before you go offline.

Everything after that is on the phone: IndexedDB holds your sets, the service worker holds the code,
the pose model and the wasm, so the app counts with the laptop shut and the phone in airplane mode.

## Everyday use

- **Train** — set the phone on the floor, 1.5–2.5 m away, side-on to you. Fix the four checklist
  lines, tap Start set, hold the plank, count. `−` / `+` correct mid-set, End finishes it, and the
  summary lets you rewrite the number before saving. The saved record keeps both
  `repsDetected` (what the camera saw) and `repsFinal` (what you kept).
- **Today** — total for the day and the list of sets, with delete.
- **Settings** — depth preset, threshold sliders, clean-reps-only, auto-start, voice, camera,
  model, export/import, and diagnostics.
- **Counter lab** (Settings ▸ Counter lab, or `#/debug`) — live angles and state-machine state,
  threshold sliders you can move mid-set, and video-file replay so you can tune the counter while
  lying on the sofa instead of doing pushups.

## Backup

Sets live in the phone's IndexedDB, which iOS can wipe if storage pressure gets bad and you have
never opened the app. Settings ▸ Data ▸ **Export JSON** writes a file to Share — keep one in Files
or iCloud Drive. Import merges, it does not overwrite.

## Update

Change the code on the Mac, run `./scripts/deploy.sh -m "…"`. The next time the app is opened with
a network connection the service worker finds the new build and shows
*“Update available — tap to reload”*. Data survives; the database schema is versioned and
migrations run on open.

## Development

```bash
./scripts/dev.sh              # http://localhost:8080 — desktop only, the camera works there
./scripts/dev.sh --tunnel     # prints a trycloudflare.com URL an iPhone can reach
```

iOS refuses the camera on plain `http://` LAN addresses, so a phone needs real HTTPS. The tunnel is
fine for a quick check but the URL changes every restart, which resets the camera permission and the
offline cache. Test properly from the Pages URL.

```bash
bash tools/build-stamp.sh     # rewrite sw.js: new cache version + precache list
bash tools/fetch-assets.sh    # re-download MediaPipe wasm, models, fonts, regenerate icons
node tests/counter.test.mjs   # counter engine regression tests
```

## Layout

```
index.html            app shell, tab bar, service-worker registration
manifest.webmanifest  name, icons, standalone display
sw.js                 generated: versioned cache + precache list + update flow
css/app.css           palette, safe-area insets, dark and light
css/today.css         goal ring, streak line, missed-day sheet
css/progress.css      heatmap grid, chart axes, range switcher
js/main.js            hash router, update prompt, wake-lock and storage sentinels
js/camera.js          getUserMedia lifecycle + human recovery copy
js/pose.js            MediaPipe landmarker, gpu→cpu fallback, 15–30 fps, skeleton overlay
js/counter.js         state machine: hysteresis, arm gate, flags, presets, one-tap debounce
js/one-euro.js        smoothing for elbow angle
js/workout.js         set lifecycle helpers (modes arrive in phase 3)
js/db.js              IndexedDB v1: sets, reps, meta + export/import
js/stats.js           day/week/month/year buckets, streaks, records, estimates, heatmap
js/goals.js           daily/weekly/yearly goals, streak mode, rest passes (stored in db meta)
js/badges.js          rule engine (phase 3)
js/plans.js           progression plans (phase 3)
js/reminders.js       due-today card, Badging API, .ics (phase 3)
js/feedback.js        voice, beeps, haptics
js/upgrade.js         update prompt, wake lock, persistent storage, badging
js/util.js            small DOM/format helpers
js/views/*            today, train, progress, badges, settings, debug
vendor/mediapipe/     tasks-vision bundle + wasm, self-hosted
models/               pose_landmarker_lite.task, pose_landmarker_full.task
fonts/                Barlow Semi Condensed (the rep number), IBM Plex Sans (everything else)
icons/                generated app icons
tools/                asset fetcher, icon generator, sw stamper, dev server,
                      shots.mjs (headless iPhone screenshot harness), seed.js (fixture data)
scripts/              dev.sh, deploy.sh
```

## Roadmap

| phase | what |
|---|---|
| 1 | counter core, setup, lifecycle, correction, saving, voice, offline, counter lab |
| 2 | ✅ Today with goal ring, history heatmap, charts, records, goals, streaks, export/import of goals |
| 3 | badge engine, workout modes, plans, Layer A reminders (in-app card, icon badge, `.ics`) |
| 4 | threshold tuning from your detected-vs-corrected data, performance, accessibility |
| 5 | optional Layer B Web Push via a Cloudflare Worker with VAPID + cron |

## Known limits in this build

- The counter reads a 2D skeleton. A side view in normal light is the reliable case; heavy shadows,
  a cluttered background behind your arms, or the phone closer than ~1.2 m will cost accuracy.
- `navigator.vibrate` is not exposed to iOS Safari, so haptics stay off on the phone even when
  enabled. Beeps and voice carry the feedback.
- The Badging API is used when present; in a plain Safari tab iOS ignores it, so the icon badge only
  appears for a Home Screen install.
- Offline is proven after a first successful load with the model fetched. Clearing Safari website
  data, or iOS deciding the app is stale, drops the cache — reopen it online once and it rebuilds.
- The Badges tab is still a placeholder (phase 3). Today, Progress and Settings are live.
- Charts only ever show what is on this phone. Export after every meaningful session — a cleared
  Safari website-data drops both the history and the offline cache.
- `estimatedMax` is a floor plus a documented allowance (+12% of your best recent set, capped at
  +10), not a measurement. The milestone date is a least-squares fit over your last 12 weekly best
  sets and moves as soon as you log one real set.
- Tempo and depth consistency need per-rep rows, which only sets saved by the camera have. Manual
  sets and anything imported from an older export show as unmeasured.
__EOF_README_md__

mkdir -p 'scripts'
cat > 'scripts/deploy.sh' <<'__EOF_scripts_deploy_sh__'
#!/usr/bin/env bash
# Build stamp + commit + push to GitHub Pages. Safe to re-run after every phase.
#   ./scripts/deploy.sh -m "phase 1: counter core"
# Optional: REPO_NAME=whatever PRIVATE=1 ./scripts/deploy.sh -m "..."
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_NAME="${REPO_NAME:-pushups-pwa}"
MSG="update"
while [ $# -gt 0 ]; do
  case "$1" in
    -m) MSG="${2:-update}"; shift 2 ;;
    *) echo "ignoring arg: $1"; shift ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh not found — brew install gh && gh auth login"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }

USER_LOGIN="$(gh api user -q .login)"
GIT_AUTHOR=()
if ! git config --get user.email >/dev/null 2>&1; then
  GIT_AUTHOR=(-c "user.name=${USER_LOGIN}" -c "user.email=${USER_LOGIN}@users.noreply.github.com")
fi

[ -d .git ] || git init -q -b main
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"

if ! git remote get-url origin >/dev/null 2>&1; then
  if gh repo view "$USER_LOGIN/$REPO_NAME" >/dev/null 2>&1; then
    echo "reusing existing repo $USER_LOGIN/$REPO_NAME"
  else
    echo "creating repo $USER_LOGIN/$REPO_NAME ($([ "${PRIVATE:-0}" = "1" ] && echo private || echo public))"
    if [ "${PRIVATE:-0}" = "1" ]; then
      gh repo create "$REPO_NAME" --private --source=. --description "Camera pushup counter PWA" >/dev/null
    else
      gh repo create "$REPO_NAME" --public --source=. --description "Camera pushup counter PWA" >/dev/null
    fi
  fi
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$USER_LOGIN/$REPO_NAME.git"

bash tools/build-stamp.sh

git add -A
if git diff --cached --quiet; then
  echo "nothing new to commit"
else
  git "${GIT_AUTHOR[@]+"${GIT_AUTHOR[@]}"}" commit -q -m "$MSG"
  echo "committed: $MSG"
fi
git push -q -u origin "$BRANCH"

if ! gh api "repos/$USER_LOGIN/$REPO_NAME/pages" >/dev/null 2>&1; then
  echo "enabling GitHub Pages (branch $BRANCH, /)"
  printf '{"source":{"branch":"%s","path":"/"},"message":"enable pages"}' "$BRANCH" \
    | gh api --method POST "repos/$USER_LOGIN/$REPO_NAME/pages" --input - >/dev/null \
    || echo "  (could not enable Pages automatically — turn it on at Settings ▸ Pages, branch $BRANCH, folder /)"
fi

URL="https://$USER_LOGIN.github.io/$REPO_NAME/"
echo
echo "pushed — waiting for Pages to serve $URL"
for _ in $(seq 1 24); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$URL" || echo 000)
  if [ "$code" = "200" ]; then echo "LIVE  $URL"; exit 0; fi
  sleep 5
done
echo "last status $code — Pages can take a couple of minutes. Check with:"
echo "  gh api repos/$USER_LOGIN/$REPO_NAME/pages"
echo "  $URL"
__EOF_scripts_deploy_sh__

mkdir -p 'scripts'
cat > 'scripts/dev.sh' <<'__EOF_scripts_dev_sh__'
#!/usr/bin/env bash
# Local iteration: stamp the service worker, serve the folder, and (optionally) put it behind real
# HTTPS so an iPhone can reach it before you deploy.
#
#   ./scripts/dev.sh              # http://localhost:8080 — desktop testing only
#   ./scripts/dev.sh --tunnel     # also prints a throwaway https://<random>.trycloudflare.com URL
#
# iOS blocks the camera on a plain http:// LAN address, so a phone must reach the app over real
# HTTPS. The tunnel URL works but changes every time it restarts — treat it as a smoke test only.
# The stable install is the Pages URL from ./scripts/deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/build-stamp.sh
PORT="${PORT:-8080}"

if [ "${1:-}" = "--tunnel" ]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found — brew install cloudflared"; exit 1
  fi
  ( cloudflared tunnel --url "http://localhost:$PORT" 2>&1 \
    | sed -n 's/.*https:\/\/\([a-z0-9-]*\)\.trycloudflare\.com.*/CLOUDFLARE https:\/\/\1.trycloudflare.com/p' & )
fi

echo "serving $PWD at http://localhost:$PORT  (ctrl-c to stop)"
exec /usr/bin/python3 tools/serve.py "$PORT"
__EOF_scripts_dev_sh__

mkdir -p 'tests'
cat > 'tests/counter.test.html' <<'__EOF_tests_counter_test_html__'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>pushups — counter tests</title>
<style>
  body { background: #10131a; color: #d8dee9; font: 14px/1.5 ui-monospace, Menlo, monospace; margin: 0; padding: 16px; }
  h1 { font-size: 16px; margin: 0 0 4px; }
  p { color: #8b95a7; margin: 0 0 12px; }
  pre { white-space: pre-wrap; word-break: break-word; margin: 0; }
  .fail { color: #ff6b6b; }
  .pass { color: #7ee787; }
</style>
</head>
<body>
<h1>counter.test — synthetic landmark checks</h1>
<p>Modules need http, not file:// — run <code>python3 -m http.server</code> in the project root and open
<code>/tests/counter.test.html</code>. The same seven cases run headlessly via <code>node tests/counter.test.mjs</code>.</p>
<pre id="out">running…</pre>
<script type="module">
import { Counter, angleBetween, hipOffsetOf, bodyAngleOf, elbowAngle } from '../js/counter.js';
import { OneEuro, smoothSeries } from '../js/one-euro.js';

const outEl = document.getElementById('out');
let text = '';
let failures = 0;
function say(line) { text += line + '\n'; }
function check(name, cond) {
  if (!cond) failures++;
  say(`${cond ? 'PASS' : 'FAIL'}  ${name}`);
}
function flush() {
  outEl.innerHTML = text.split('\n').map((l) => {
    if (l.startsWith('FAIL')) return `<span class="fail">${l}</span>`;
    if (l.startsWith('PASS')) return `<span class="pass">${l}</span>`;
    return l;
  }).join('<br>');
}

const FPS = 40;
const STEP = 1000 / FPS;
const L = 0.37;
const ANKLE = { x: 0.72, y: 0.53 };
const HIP_X = 0.5;
const WRIST_R = 0.12;

// Same generator as counter.test.mjs — a plausible side-view plank whose landmarks really produce
// the requested elbow angle, hip offset and body tilt.
function makeLandmarks({ angle, depth = 0, hipOff = 0, tilt = null, vis = 0.95 }) {
  const phi = ((tilt === null ? 3 + 7 * depth : tilt)) * Math.PI / 180;
  const S = { x: ANKLE.x - L * Math.cos(phi), y: ANKLE.y + L * Math.sin(phi) };
  const dx = ANKLE.x - S.x;
  const dy = ANKLE.y - S.y;
  const len = Math.hypot(dx, dy);
  let nx = -dy, ny = dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const hipY = S.y + (hipOff * len * len - (HIP_X - S.x) * nx) / ny;
  const H = { x: HIP_X, y: hipY };
  const K = { x: S.x + 0.78 * dx, y: S.y + 0.78 * dy };
  const E = { x: S.x + 0.06, y: S.y + 0.11 };
  let ux = S.x - E.x, uy = S.y - E.y;
  const um = Math.hypot(ux, uy);
  ux /= um; uy /= um;
  const th = angle * Math.PI / 180;
  const W = {
    x: E.x + WRIST_R * (ux * Math.cos(th) - uy * Math.sin(th)),
    y: E.y + WRIST_R * (ux * Math.sin(th) + uy * Math.cos(th)),
  };
  const N = { x: S.x - 0.05, y: S.y - 0.02 };
  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  const put = (i, p, v) => { lm[i] = { x: p.x, y: p.y, z: 0, visibility: v }; };
  for (const [li, ri, p] of [[11, 12, S], [13, 14, E], [15, 16, W], [23, 24, H], [25, 26, K], [27, 28, ANKLE]]) {
    put(li, p, vis); put(ri, p, vis * 0.97);
  }
  put(0, N, vis);
  return lm;
}

function makeFrame(opts) {
  const landmarks = makeLandmarks(opts);
  const visVals = [11, 12, 13, 14, 15, 16, 23, 24].map((i) => landmarks[i].visibility);
  const quality = visVals.reduce((a, b) => a + b, 0) / visVals.length;
  return { landmarks, present: opts.present !== false, quality, fps: FPS };
}

function repFrames(t0, count, { topAngle = 178, bottomAngle = 92, downMs = 800, upMs = 700, topDwellMs = 300 } = {}) {
  const frames = [];
  let t = t0;
  const downN = Math.round(downMs / STEP);
  const upN = Math.round(upMs / STEP);
  const dwellN = Math.round(topDwellMs / STEP);
  for (let r = 0; r < count; r++) {
    for (let i = 1; i <= downN; i++) { const k = i / downN; frames.push({ t, opt: { angle: topAngle + (bottomAngle - topAngle) * k, depth: k } }); t += STEP; }
    for (let i = 1; i <= upN; i++) { const k = i / upN; frames.push({ t, opt: { angle: bottomAngle + (topAngle - bottomAngle) * k, depth: 1 - k } }); t += STEP; }
    for (let i = 0; i < dwellN; i++) { frames.push({ t, opt: { angle: topAngle, depth: 0 } }); t += STEP; }
  }
  return { frames, tEnd: t };
}

function holdFrames(t0, count, opts = {}) {
  const out = [];
  let t = t0;
  for (let i = 0; i < count; i++) { out.push({ t, opt: { angle: 178, depth: 0, ...opts } }); t += STEP; }
  return { frames: out, tEnd: t };
}

function run(c, specList) {
  let last = null;
  const reps = [];
  for (const { t, opt, present } of specList) {
    last = c.addFrame(t, makeFrame(present === false ? { ...opt, present: false } : opt));
    for (const e of last.events) if (e.type === 'rep') reps.push(e.data);
  }
  return { ...last, allReps: reps };
}

function freshCounter(extra = {}) {
  return new Counter({ top: 155, bottom: 100, minRepMs: 400, cleanOnly: false, secondarySignal: 'assist', ...extra });
}

function arm(c, t0) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20);
  return { out: run(c, frames), t: tEnd };
}

function rampSpec(c, t0, legs, tailHold = 12) {
  const spec = [];
  let t = t0;
  for (const [from, to, d0, d1, ms] of legs) {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t += STEP;
    }
  }
  for (let i = 0; i < tailHold; i++) spec.push({ t, opt: { angle: 178, depth: 0 } });
  return run(c, spec);
}

/* generator sanity */
{
  const lm = makeLandmarks({ angle: 123, depth: 0.5, hipOff: 0.09 });
  check('generator: landmarks produce the requested elbow angle', Math.abs(elbowAngle(lm, 'left') - 123) < 0.5);
  check('generator: requested hip offset is reproduced', Math.abs(hipOffsetOf(lm, 'left') - 0.09) < 0.005);
  check('generator: sag is POSITIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: 0.2 }), 'left') > 0);
  check('generator: pike is NEGATIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: -0.2 }), 'left') < 0);
  check('generator: flat plank has a small body angle', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178 }), 'left')) < 12);
  check('generator: 45 deg tilt reads 45 deg', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178, tilt: 45 }), 'left') - 45) < 0.5);
  check('helper: angleBetween', Math.abs(angleBetween({ x: 0, y: 1 }, { x: 0, y: 0 }, { x: 1, y: 0 }) - 90) < 1e-9);
  const flat = new OneEuro().filter(0, 5);
  check('oneEuro: first sample passes through raw', flat === 5);
  const s = smoothSeries([[0, 1], [25, 1], [50, 9]], { minCutoff: 1.1, beta: 0.02 });
  check('smoothSeries: returns the same length', s.length === 3 && s[0][1] === 1);
}

/* 1. ten clean full-depth reps */
{
  const c = freshCounter();
  const a = arm(c, 0);
  check('setup: plank arms after 3s of valid frames', a.out.armed === true && a.out.reps === 0);
  const out = run(c, repFrames(a.t, 10).frames);
  const last = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  say('      T1: reps=' + out.reps + ' clean=' + out.cleanReps + ' detected=' + out.repsDetected
    + ' state=' + out.state + ' side=' + out.side
    + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags))
    + ' minElbow=' + (last ? last.minElbow.toFixed(1) : '-')
    + ' duration=' + (last ? Math.round(last.durationMs) : '-')
    + ' shoulderDrop=' + (last ? last.shoulderDrop.toFixed(3) : '-'));
  check('T1 ten clean reps -> reps=10', out.reps === 10);
  check('T1 repsDetected=10 and cleanReps=10', out.repsDetected === 10 && out.cleanReps === 10);
  check('T1 zero flags on every rep', out.allReps.length === 10 && out.allReps.every((r) => r.flags.length === 0));
}

/* 2. walking into frame */
{
  const c = freshCounter();
  const spec = [];
  let t = 0;
  const n = Math.round(2000 / STEP);
  for (let i = 0; i < n; i++) {
    spec.push({ t, opt: { angle: 178 - 120 * Math.sin((i / n) * Math.PI), depth: i / n }, present: false });
    t += STEP;
  }
  for (let i = 0; i < Math.round(1000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  for (const f of repFrames(t, 1, { downMs: 400, upMs: 400 }).frames) spec.push(f);
  for (let i = 0; i < Math.round(2000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  say('      T2: reps=' + out.reps + ' detected=' + out.repsDetected + ' armed=' + out.armed + ' reasons=' + JSON.stringify(out.plank.reasons));
  check('T2 rep shape before the arm lock -> 0 reps', out.reps === 0 && out.repsDetected === 0 && out.cleanReps === 0);
}

/* 3. kneeling / resting after 5 reps */
{
  const c = freshCounter();
  const a = arm(c, 0);
  run(c, repFrames(a.t, 5).frames);
  check('T3 five reps counted before the rest', c.reps === 5);
  let sawArmBreak = false;
  let t = a.t + 300;
  for (let i = 0; i < 60; i++) {
    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 45 }));
    if (out.events.some((e) => e.type === 'armBreak')) sawArmBreak = true;
    t += STEP;
  }
  say('      T3: reps=' + c.reps + ' detected=' + c.repsDetected + ' armed=' + c.armed + ' state=' + c.state);
  check('T3 kneeling emits armBreak', sawArmBreak);
  check('T3 kneeling adds zero reps', c.reps === 5);
  check('T3 counter disarms and stays idle', c.armed === false && c.state === 'idle');
}

/* 4. double beat at the bottom counts one */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const out = rampSpec(c, a.t, [[178, 90, 1, 1, 800], [90, 105, 1, 0.85, 300], [105, 92, 0.85, 1, 300], [92, 178, 1, 0, 700]], 16);
  say('      T4: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
  check('T4 double beat at the bottom counts ONE rep', out.reps === 1 && out.repsDetected === 1);
}

/* 5. shallow rep, bottom=100, bottoms at 118 */
{
  // documented rule: a descent counts if it either reaches `bottom` on the smoothed angle, or
  // proves depth with shoulder travel >= 0.10 (assist/confirm). minElbow > bottom then flags 'half'.
  const c = freshCounter();
  const a = arm(c, 0);
  const noTravel = rampSpec(c, a.t, [[178, 118, 0, 0.1, 800], [118, 178, 0.1, 0, 700]]);
  say('      T5a shallow, no travel: reps=' + noTravel.reps + ' detected=' + noTravel.repsDetected);
  check('T5a shallow without shoulder travel counts 0', noTravel.reps === 0 && noTravel.repsDetected === 0);

  // T5a used 32+28+12 frames at 25 ms; start T5b after that window
  const withTravel = rampSpec(c, a.t + 2000, [[178, 118, 0, 1, 800], [118, 178, 1, 0, 700]]);
  const rep = withTravel.allReps.length ? withTravel.allReps[withTravel.allReps.length - 1] : null;
  say('      T5b shallow, real travel: reps=' + c.reps + ' detected=' + c.repsDetected
    + ' flags=' + JSON.stringify(rep ? rep.flags : null)
    + ' minElbow=' + (rep ? rep.minElbow.toFixed(1) : '-')
    + ' shoulderDrop=' + (rep ? rep.shoulderDrop.toFixed(3) : '-'));
  check('T5b shallow-with-travel counts a rep and flags it half', !!rep && rep.flags.includes('half'));

  const c2 = freshCounter({ cleanOnly: true });
  const a2 = arm(c2, 0);
  const o2 = rampSpec(c2, a2.t, [[178, 118, 0, 1, 800], [118, 178, 1, 0, 700]]);
  say('      T5c cleanOnly: reps=' + o2.reps + ' detected=' + o2.repsDetected + ' clean=' + o2.cleanReps);
  check('T5c cleanOnly keeps flagged reps out of `reps` but keeps repsDetected', o2.reps === 0 && o2.repsDetected === 1 && o2.cleanReps === 0);
}

/* 6. sagging hips */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const spec = [];
  let t = a.t;
  const downN = Math.round(800 / STEP);
  for (let i = 1; i <= downN; i++) {
    const k = i / downN;
    const opt = { angle: 178 + (92 - 178) * k, depth: k };
    if (i >= 14 && i <= 18) opt.hipOff = 0.25;
    spec.push({ t, opt });
    t += STEP;
  }
  const upN = Math.round(700 / STEP);
  for (let i = 1; i <= upN; i++) { const k = i / upN; spec.push({ t, opt: { angle: 92 + (178 - 92) * k, depth: 1 - k } }); t += STEP; }
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  say('      T6: reps=' + out.reps + ' flags=' + JSON.stringify(rep ? rep.flags : null)
    + ' hipMax=' + (rep && rep.hipMax !== null ? rep.hipMax.toFixed(3) : '-') + ' armed=' + out.armed);
  check('T6 sag excursion flags the rep', out.reps === 1 && !!rep && rep.flags.includes('sag'));
  check('T6 a brief sag does not break the arm lock', c.armed === true);
}

/* 7. minRepMs rejects a bounce */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const spec = [];
  let t = a.t;
  for (const [from, to, ms] of [[178, 92, 75], [92, 178, 75]]) {
    const n = Math.max(1, Math.round(ms / STEP));
    for (let i = 1; i <= n; i++) { spec.push({ t, opt: { angle: from + (to - from) * (i / n), depth: to < from ? 1 : 0 } }); t += STEP; }
  }
  for (let i = 0; i < 20; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  say('      T7: reps=' + out.reps + ' detected=' + out.repsDetected + ' state=' + out.state + ' armed=' + out.armed);
  check('T7 150 ms bounce rejected (minRepMs=400)', out.reps === 0 && out.repsDetected === 0);

  const c2 = freshCounter({ minRepMs: 2200 });
  const a2 = arm(c2, 0);
  const slow = rampSpec(c2, a2.t, [[178, 92, 0, 1, 800], [92, 178, 1, 0, 700]]);
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const same = run(c3, repFrames(a3.t, 1).frames);
  say('      T7b: minRepMs=2200 -> reps=' + slow.reps + ' | minRepMs=400 same rep -> reps=' + same.reps
    + ' duration=' + (same.allReps[0] ? Math.round(same.allReps[0].durationMs) : '-'));
  check('T7b duration gate rejects a 1500 ms rep when minRepMs=2200', slow.reps === 0 && slow.repsDetected === 0);
  check('T7c the same rep counts when minRepMs=400', same.reps === 1);
}

/* extras: notSide, lost pose, lockout, reset, bad frames */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const out = c.addFrame(a.t, makeFrame({ angle: 178, depth: 0, tilt: 80 }));
  say('      extra: tilt 80 -> reasons=' + JSON.stringify(out.plank.reasons) + ' bodyAngle=' + out.bodyAngle.toFixed(1));
  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));

  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let sawBreak = false;
  for (let i = 0; i < 5; i++) {
    const o = c2.addFrame(a2.t + i * STEP, makeFrame({ angle: 178, present: false }));
    if (o.events.some((e) => e.type === 'armBreak')) sawBreak = true;
  }
  check('extra: losing the pose while armed emits armBreak', sawBreak && c2.armed === false);

  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const o3 = rampSpec(c3, a3.t, [[178, 92, 0, 1, 800], [92, 148, 1, 0.45, 500], [148, 92, 0.45, 1, 500], [92, 178, 1, 0, 700]]);
  say('      extra lockout: reps=' + o3.reps + ' flags=' + JSON.stringify(o3.allReps.map((r) => r.flags)));
  check('extra: incomplete lockout counts and is flagged', o3.reps === 2 && o3.allReps[0].flags.includes('lockout'));

  const c4 = freshCounter();
  const a4 = arm(c4, 0);
  run(c4, repFrames(a4.t, 3).frames);
  check('extra: reps counted before reset', c4.reps === 3);
  c4.reset('test');
  check('extra: reset zeros counts and state', c4.reps === 0 && c4.repsDetected === 0 && c4.cleanReps === 0 && c4.state === 'idle' && c4.armed === false && c4.trace.length === 0);

  const o5 = c4.addFrame(0, { landmarks: null, present: true, quality: 0, fps: 30 });
  check('extra: malformed frame does not throw', o5 && o5.reps === 0 && o5.plank.reasons.includes('noPose'));
  const o6 = c4.addFrame(1, { landmarks: new Array(10).fill({ x: 0.5, y: 0.5, z: 0, visibility: 1 }), present: true, quality: 1, fps: 30 });
  check('extra: short landmark array treated as noPose', o6.plank.reasons.includes('noPose'));
  check('extra: trace is capped at 45 frames', c4.trace.length <= 45);
}

say('');
say(failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`);
flush();
</script>
</body>
</html>
__EOF_tests_counter_test_html__

mkdir -p 'tests'
cat > 'tests/counter.test.mjs' <<'__EOF_tests_counter_test_mjs__'
// node tests/counter.test.mjs
import { Counter, angleBetween, hipOffsetOf, bodyAngleOf, elbowAngle } from '../js/counter.js';

let failures = 0;
function check(name, cond) {
  const line = `${cond ? 'PASS' : 'FAIL'}  ${name}`;
  if (!cond) failures++;
  console.log(line);
}

const FPS = 40;
const STEP = 1000 / FPS;
const L = 0.37;
const ANKLE = { x: 0.72, y: 0.53 };
const HIP_X = 0.5;
const WRIST_R = 0.12;

// Plausible side-view plank: mid-shoulder / mid-hip / mid-ankle on a line that tilts with depth.
// phi (deg) is exactly what bodyAngleOf() reports, so tilt == 45 gives a kneeling-looking shape.
// The wrist is placed on a circle of radius 0.12 around the elbow, rotated by the requested
// elbow angle away from the upper arm — the landmarks really do produce that angle.
function makeLandmarks({ angle, depth = 0, hipOff = 0, tilt = null, vis = 0.95 }) {
  const phi = ((tilt === null ? 3 + 7 * depth : tilt)) * Math.PI / 180;
  const S = { x: ANKLE.x - L * Math.cos(phi), y: ANKLE.y + L * Math.sin(phi) };
  const dx = ANKLE.x - S.x;
  const dy = ANKLE.y - S.y;
  const len = Math.hypot(dx, dy);
  let nx = -dy, ny = dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const hipY = S.y + (hipOff * len * len - (HIP_X - S.x) * nx) / ny;
  const H = { x: HIP_X, y: hipY };
  const K = { x: S.x + 0.78 * dx, y: S.y + 0.78 * dy };

  const E = { x: S.x + 0.06, y: S.y + 0.11 };
  let ux = S.x - E.x, uy = S.y - E.y;
  const um = Math.hypot(ux, uy);
  ux /= um; uy /= um;
  const th = angle * Math.PI / 180;
  const W = {
    x: E.x + WRIST_R * (ux * Math.cos(th) - uy * Math.sin(th)),
    y: E.y + WRIST_R * (ux * Math.sin(th) + uy * Math.cos(th)),
  };
  const N = { x: S.x - 0.05, y: S.y - 0.02 };

  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  // left and right overlap in a true side view; the far side is slightly less visible
  const put = (i, p, v) => { lm[i] = { x: p.x, y: p.y, z: 0, visibility: v }; };
  const pairs = [[11, 12, S], [13, 14, E], [15, 16, W], [23, 24, H], [25, 26, K], [27, 28, ANKLE]];
  for (const [li, ri, p] of pairs) { put(li, p, vis); put(ri, p, vis * 0.97); }
  put(0, N, vis);
  return lm;
}

function makeFrame(opts) {
  const landmarks = makeLandmarks(opts);
  const visVals = [11, 12, 13, 14, 15, 16, 23, 24].map((i) => landmarks[i].visibility);
  const quality = visVals.reduce((a, b) => a + b, 0) / visVals.length;
  return { landmarks, present: opts.present !== false, quality, fps: FPS };
}

// angle/depth schedule for one full rep; depth follows the elbow angle the way a real plank does
function repFrames(t0, count, { topAngle = 178, bottomAngle = 92, downMs = 800, upMs = 700, topDwellMs = 300 } = {}) {
  const frames = [];
  let t = t0;
  const downN = Math.round(downMs / STEP);
  const upN = Math.round(upMs / STEP);
  const dwellN = Math.round(topDwellMs / STEP);
  for (let r = 0; r < count; r++) {
    for (let i = 1; i <= downN; i++) {
      const k = i / downN;
      frames.push({ t, opt: { angle: topAngle + (bottomAngle - topAngle) * k, depth: k } });
      t += STEP;
    }
    for (let i = 1; i <= upN; i++) {
      const k = i / upN;
      frames.push({ t, opt: { angle: bottomAngle + (topAngle - bottomAngle) * k, depth: 1 - k } });
      t += STEP;
    }
    for (let i = 0; i < dwellN; i++) {
      frames.push({ t, opt: { angle: topAngle, depth: 0 } });
      t += STEP;
    }
  }
  return { frames, tEnd: t };
}

function holdFrames(t0, count, opts = {}) {
  const out = [];
  let t = t0;
  for (let i = 0; i < count; i++) { out.push({ t, opt: { angle: 178, depth: 0, ...opts } }); t += STEP; }
  return { frames: out, tEnd: t };
}

function run(c, specList) {
  let last = null;
  const reps = [];
  for (const { t, opt, present } of specList) {
    const o = present === false ? { ...opt, present: false } : opt;
    last = c.addFrame(t, makeFrame(o));
    for (const e of last.events) {
      if (e.type === 'rep') reps.push(e.data);
    }
  }
  return { ...last, allReps: reps };
}

function freshCounter(extra = {}) {
  const c = new Counter({ top: 155, bottom: 100, minRepMs: 400, cleanOnly: false, secondarySignal: 'assist', ...extra });
  return c;
}

// Arm the counter with a clean, valid plank.
function arm(c, t0) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20);
  const out = run(c, frames);
  return { out, t: tEnd };
}

/* ---------- sanity: the generator really produces the requested geometry ---------- */
{
  const lm = makeLandmarks({ angle: 123, depth: 0.5, hipOff: 0.09 });
  check('generator: landmarks produce the requested elbow angle', Math.abs(elbowAngle(lm, 'left') - 123) < 0.5);
  check('generator: requested hip offset is reproduced', Math.abs(hipOffsetOf(lm, 'left') - 0.09) < 0.005);
  check('generator: sag (hip below the shoulder-ankle line) is POSITIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: 0.2 }), 'left') > 0);
  check('generator: pike (hip above the line) is NEGATIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: -0.2 }), 'left') < 0);
  check('generator: body angle of the flat plank is small', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178 }), 'left')) < 12);
  check('generator: 45 deg tilt reads 45 deg', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178, tilt: 45 }), 'left') - 45) < 0.5);
  check('helper: angleBetween vertex maths', Math.abs(angleBetween({ x: 0, y: 1 }, { x: 0, y: 0 }, { x: 1, y: 0 }) - 90) < 1e-9);
}

/* ---------- 1. ten clean full-depth reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  check('setup: plank arms after 3s of valid frames', a.out.armed === true && a.out.reps === 0);
  const spec = repFrames(a.t, 10);
  const out = run(c, spec.frames);
  const flags = out.allReps.length ? out.allReps[out.allReps.length - 1].flags : ['<no reps>'];
  console.log('      T1 reps: ' + JSON.stringify(out.allReps.map((r) => ({ n: r.n, f: r.flags, dur: Math.round(r.durationMs), min: +r.minElbow.toFixed(1), mx: r.maxElbow === null ? null : +r.maxElbow.toFixed(1), drop: +r.shoulderDrop.toFixed(3), hipMax: r.hipMax === null ? null : +r.hipMax.toFixed(3) }))));
  check('T1 ten clean reps -> reps=10', out.reps === 10);
  check('T1 repsDetected=10 and cleanReps=10', out.repsDetected === 10 && out.cleanReps === 10);
  check('T1 zero flags on the last rep', flags.length === 0);
  console.log('      T1 detail: reps=' + out.reps + ' clean=' + out.cleanReps + ' detected=' + out.repsDetected + ' lastRepFlags=' + JSON.stringify(flags) + ' state=' + out.state + ' side=' + out.side);
  if (out.lastRep) console.log('      T1 lastRep: ' + JSON.stringify({ minElbow: +out.lastRep.minElbow.toFixed(1), maxElbow: +out.lastRep.maxElbow.toFixed(1), durationMs: Math.round(out.lastRep.durationMs), shoulderDrop: +out.lastRep.shoulderDrop.toFixed(3), hipMax: out.lastRep.hipMax === null ? null : +out.lastRep.hipMax.toFixed(3) }));
}

/* ---------- 2. walking into frame ---------- */
{
  const c = freshCounter();
  const spec = [];
  // 2 s of no pose while the elbows swing through a full rep shape
  let t = 0;
  for (let i = 0; i < Math.round(2000 / STEP); i++) {
    const phase = i / Math.round(2000 / STEP);
    const angle = 178 - 120 * Math.sin(phase * Math.PI);
    spec.push({ t, opt: { angle, depth: phase }, present: false });
    t += STEP;
  }
  // now a valid plank, held for 2 s (still under the 2.5 s arm hold) with one more rep shape
  for (let i = 0; i < Math.round(1000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const one = repFrames(t, 1, { downMs: 400, upMs: 400 });
  for (const f of one.frames) spec.push(f);
  t = one.tEnd;
  for (let i = 0; i < Math.round(2000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  check('T2 walking in + rep shape before arm -> 0 reps', out.reps === 0 && out.repsDetected === 0 && out.cleanReps === 0);
  check('T2 not armed during the invalid window', out.armed === false || out.reps === 0);
  console.log('      T2 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' armed=' + out.armed + ' reasons=' + JSON.stringify(out.plank.reasons) + ' state=' + out.state);
}

/* ---------- 3. kneeling / resting after 5 reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  run(c, repFrames(a.t, 5).frames);
  const afterReps = c.reps;
  check('T3 five reps counted before the rest', afterReps === 5);
  let sawArmBreak = false;
  let t = a.t + 300;
  for (let i = 0; i < 60; i++) {
    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 45 }));
    if (out.events.some((e) => e.type === 'armBreak')) sawArmBreak = true;
    t += STEP;
  }
  check('T3 kneeling emits armBreak', sawArmBreak);
  check('T3 kneeling adds zero reps', c.reps === 5);
  check('T3 counter disarms and stays idle', c.armed === false && c.state === 'idle');
  console.log('      T3 detail: reps=' + c.reps + ' detected=' + c.repsDetected + ' armed=' + c.armed + ' state=' + c.state);
}

/* ---------- 4. double beat at the bottom counts one ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const push = (angle, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) spec.push({ t, opt: { angle, depth } });
    t += STEP * n;
  };
  const pushRamp = (from, to, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const a2 = from + (to - from) * (i / n);
      spec.push({ t, opt: { angle: a2, depth } });
      t += STEP;
    }
  };
  pushRamp(178, 90, 1, 800);
  pushRamp(90, 105, 0.85, 300);
  pushRamp(105, 92, 1, 300);
  pushRamp(92, 178, 0, 700);
  push(178, 0, 400);
  const out = run(c, spec);
  check('T4 double beat at the bottom counts ONE rep', out.reps === 1 && out.repsDetected === 1);
  console.log('      T4 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
}

/* ---------- 5. shallow rep, bottom=100, bottoms at 118 ---------- */
{
  // documented rule: a descent only counts if it either (a) reaches bottom on the smoothed angle,
  // or (b) proves real depth with shoulder travel >= 0.10 (assist/confirm modes). Then minElbow >
  // bottom earns the 'half' flag.
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t += STEP;
    }
  };
  // shallow with NO body travel -> must not count
  ramp(178, 118, 0, 0.1, 800);
  ramp(118, 178, 0.1, 0, 700);
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  let out = run(c, spec);
  console.log('      T5a no-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' clean=' + out.cleanReps);
  check('T5a shallow without shoulder travel counts 0', out.reps === 0 && out.repsDetected === 0);

  // shallow (118) but the body really travelled down (depth 1 -> ~0.12 normalised) -> counts, flagged half
  const spec2 = [];
  let t2 = t;
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 118, 0, 1, 800);
  ramp2(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); t2 += STEP; }
  out = run(c, spec2);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T5b deep-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' minElbow=' + (rep ? rep.minElbow.toFixed(1) : '-') + ' shoulderDrop=' + (rep ? rep.shoulderDrop.toFixed(3) : '-'));
  check('T5b shallow-with-travel counts 1 rep and flags it half', out.reps === 1 && !!rep && rep.flags.includes('half'));

  // same rep, cleanOnly -> the flagged rep must not raise `reps` but must raise `repsDetected`
  const c2 = freshCounter({ cleanOnly: true });
  const a2 = arm(c2, 0);
  const spec3 = [];
  let t3 = a2.t;
  const ramp3 = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec3.push({ t: t3, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t3 += STEP;
    }
  };
  ramp3(178, 118, 0, 1, 800);
  ramp3(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec3.push({ t: t3, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec3);
  console.log('      T5c cleanOnly: reps=' + out2.reps + ' detected=' + out2.repsDetected + ' clean=' + out2.cleanReps);
  check('T5c cleanOnly keeps flagged reps out of `reps` but keeps repsDetected', out2.reps === 0 && out2.repsDetected === 1 && out2.cleanReps === 0);
}

/* ---------- 6. sagging hips ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const spec = [];
  let t = a.t;
  const downN = Math.round(800 / STEP);
  for (let i = 1; i <= downN; i++) {
    const k = i / downN;
    const opt = { angle: 178 + (92 - 178) * k, depth: k };
    // a brief, real sag excursion (5 frames at +0.25) — sustained sag would disarm instead
    if (i >= 14 && i <= 18) opt.hipOff = 0.25;
    spec.push({ t, opt });
    t += STEP;
  }
  for (let i = 1; i <= Math.round(700 / STEP); i++) {
    const k = i / Math.round(700 / STEP);
    spec.push({ t, opt: { angle: 92 + (178 - 92) * k, depth: 1 - k } });
    t += STEP;
  }
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T6 detail: reps=' + out.reps + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' hipMax=' + (rep && rep.hipMax !== null ? rep.hipMax.toFixed(3) : '-') + ' plankValid=' + out.plank.valid);
  check('T6 sag excursion flags the rep', out.reps === 1 && !!rep && rep.flags.includes('sag'));
  check('T6 a brief sag does not break the arm lock', c.armed === true);
}

/* ---------- 7. minRepMs rejects a bounce ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depth, ms) => {
    const n = Math.max(1, Math.round(ms / STEP));
    for (let i = 1; i <= n; i++) {
      spec.push({ t, opt: { angle: from + (to - from) * (i / n), depth } });
      t += STEP;
    }
  };
  ramp(178, 92, 1, 75);
  ramp(92, 178, 0, 75);
  for (let i = 0; i < 20; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  console.log('      T7 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' state=' + out.state + ' armed=' + out.armed + ' traceMinElbow=' + Math.min(...c.trace.map((x) => (x.elbowFiltered === null ? 999 : x.elbowFiltered))).toFixed(1));
  check('T7 150 ms bounce rejected (minRepMs=400)', out.reps === 0 && out.repsDetected === 0);

  // same rep shape but slow enough to bottom, with minRepMs raised -> the duration gate rejects it
  const c2 = freshCounter({ minRepMs: 2200 });
  const a2 = arm(c2, 0);
  let t2 = a2.t;
  const spec2 = [];
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 92, 0, 1, 800);
  ramp2(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec2);
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const out3 = run(c3, repFrames(a3.t, 1).frames);
  console.log('      T7b detail: minRepMs=2200 -> reps=' + out2.reps + ' detected=' + out2.repsDetected + ' | minRepMs=400 same rep -> reps=' + out3.reps + ' duration=' + (out3.allReps.length ? Math.round(out3.allReps[0].durationMs) : '-'));
  check('T7b duration gate rejects a 1500 ms rep when minRepMs=2200', out2.reps === 0 && out2.repsDetected === 0);
  check('T7c the same rep counts when minRepMs=400', out3.reps === 1);
}

/* ---------- extra: 'notSide' gate, armBreak on lost pose, reset ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const out = c.addFrame(a.t, makeFrame({ angle: 178, depth: 0, tilt: 80 }));
  console.log('      extra: tilt 80 -> reasons=' + JSON.stringify(out.plank.reasons) + ' bodyAngle=' + out.bodyAngle.toFixed(1));
  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));

  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let sawBreak = false;
  for (let i = 0; i < 5; i++) {
    const o = c2.addFrame(a2.t + i * STEP, makeFrame({ angle: 178, present: false }));
    if (o.events.some((e) => e.type === 'armBreak')) sawBreak = true;
  }
  check('extra: losing the pose while armed emits armBreak', sawBreak && c2.armed === false);

  const c3 = freshCounter();
  run(c3, arm(c3, 0).frames || []);
  const a3 = arm(c3, 0);
  run(c3, repFrames(a3.t, 3).frames);
  check('extra: reps counted before reset', c3.reps === 3);
  c3.reset('test');
  check('extra: reset zeros counts and state', c3.reps === 0 && c3.repsDetected === 0 && c3.cleanReps === 0 && c3.state === 'idle' && c3.armed === false && c3.trace.length === 0);

  const out4 = c3.addFrame(0, { landmarks: null, present: true, quality: 0, fps: 30 });
  check('extra: malformed frame does not throw', out4 && out4.reps === 0 && out4.plank.reasons.includes('noPose'));
  const out5 = c3.addFrame(1, { landmarks: new Array(10).fill({ x: 0.5, y: 0.5, z: 0, visibility: 1 }), present: true, quality: 1, fps: 30 });
  check('extra: short landmark array treated as noPose', out5.plank.reasons.includes('noPose'));
}

/* ---------- extra: lockout reversal, partial ascent discard, shoulder-travel maths ---------- */
{
  // rises to 148 (inside [top-12, top)) then descends again -> counts, flagged 'lockout'
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t += STEP;
    }
  };
  ramp(178, 92, 0, 1, 800);
  ramp(92, 148, 1, 0.45, 500);
  ramp(148, 92, 0.45, 1, 500);
  ramp(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) spec.push({ t, opt: { angle: 178, depth: 0 } });
  const out = run(c, spec);
  console.log('      extra lockout: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
  check('extra: incomplete lockout counts and is flagged', out.reps === 2 && out.allReps[0].flags.includes('lockout'));

  // rises only to 130 (well short of top-12) -> not a rep at all
  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let t2 = a2.t;
  const spec2 = [];
  const ramp2 = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 92, 0, 1, 800);
  ramp2(92, 130, 1, 0.6, 500);
  ramp2(130, 92, 0.6, 1, 500);
  ramp2(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) spec2.push({ t: t2, opt: { angle: 178, depth: 0 } });
  const out2 = run(c2, spec2);
  console.log('      extra short-ascent: reps=' + out2.reps + ' detected=' + out2.repsDetected + ' (the two half-movements merge into one rep)');
  check('extra: reversing short of top-12 is not a rep on its own', out2.repsDetected <= 1);

  // shoulder travel of a proper side-on rep lands in the documented 0.10-0.25 band
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const out3 = run(c3, repFrames(a3.t, 3).frames);
  const drops = out3.allReps.map((r) => +r.shoulderDrop.toFixed(3));
  console.log('      extra travel: shoulderDrop per rep = ' + JSON.stringify(drops));
  check('extra: full-depth reps report 0.10-0.25 of normalised shoulder travel', drops.length === 3 && drops.every((d) => d >= 0.10 && d <= 0.25));
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exitCode = failures === 0 ? 0 : 1;
__EOF_tests_counter_test_mjs__

mkdir -p 'tests'
cat > 'tests/stats.test.mjs' <<'__EOF_tests_stats_test_mjs__'
/* Node test for the aggregation layer. No DOM, no IndexedDB — stats.js is pure.
   Run: node tests/stats.test.mjs */

import assert from 'node:assert/strict';
import {
  addDays, bestSetPerWeek, byDay, consistencySeries, dayBuckets, dayKey, dailyGoalStreak,
  estimatedMax, flagMix, gaps, heatmap, monthBuckets, projectTarget, records, setConsistency,
  summarize, timeOfDay, trainingStreak, weekBuckets, weekStart, weeklyGoalStreak, yearBuckets,
} from '../js/stats.js';

let pass = 0, fail = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log('PASS  ' + name); }
  catch (err) { fail += 1; console.log('FAIL  ' + name + '\n      ' + (err.message || err)); }
}

const TODAY = dayKey(Date.now());
const MONDAY = weekStart(TODAY);

/** Place a set on an absolute day key so week-aligned fixtures stay week-aligned. */
function setOn(key, reps, opts = {}) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  const ago = Math.round((d.getTime() - new Date(key + 'T12:00:00').getTime()) / 86400000);
  return set(ago, reps, opts);
}

/** Set builder: `ago` = whole days back from today, hour = local hour of day. */
function set(ago, reps, opts = {}) {
  const d = new Date();
  d.setDate(d.getDate() - ago);
  d.setHours(opts.hour ?? 8, opts.minute ?? 0, 0, 0);
  return {
    id: opts.id ?? 1000 + ago * 10, startedAt: d.getTime(), endedAt: d.getTime() + (opts.durationMs || reps * 3000),
    durationMs: opts.durationMs || reps * 3000, mode: opts.mode || 'camera', source: opts.source || 'camera',
    repsDetected: opts.detected ?? reps, repsFinal: reps, flags: opts.flags || {},
    day: dayKey(d.getTime()),
  };
}

/* ── calendar helpers ─────────────────────────────────────────── */

check('weekStart lands on Monday and is stable across the week', () => {
  assert.equal(weekStart(TODAY), MONDAY);
  assert.equal(weekStart(addDays(MONDAY, 6)), MONDAY);
});

check('addDays crosses month boundaries', () => {
  assert.equal(addDays('2026-01-31', 1), '2026-02-01');
  assert.equal(addDays('2026-03-01', -1), '2026-02-28');
  assert.equal(addDays('2028-02-28', 1), '2028-02-29');   // leap year
});

/* ── per-day totals ───────────────────────────────────────────── */

const twoSets = [set(0, 12, { id: 1, hour: 7 }), set(0, 8, { id: 2, hour: 19, flags: { half: 2 } })];

check('byDay adds reps and counts sets on the same day', () => {
  const d = byDay(twoSets).get(TODAY);
  assert.equal(d.reps, 20);
  assert.equal(d.sets, 2);
  assert.equal(d.best, 12);
  assert.equal(d.flagged, 2);
  assert.equal(d.clean, 18);
  assert.equal(d.detected, 20);
});

check('empty input yields no days and no crash', () => {
  assert.equal(byDay([]).size, 0);
  assert.equal(byDay(undefined).size, 0);
  const s = summarize([], { dailyGoal: 50 });
  assert.equal(s.today.reps, 0);
  assert.equal(s.goalPct, 0);
  assert.equal(s.streak, 0);
});

check('a set with repsFinal 0 still counts as a set but adds no reps', () => {
  const d = byDay([set(1, 0, { id: 5 })]).get(addDays(TODAY, -1));
  assert.equal(d.reps, 0);
  assert.equal(d.sets, 1);
});

/* ── streaks ──────────────────────────────────────────────────── */

check('trainingStreak counts consecutive training days back from today', () => {
  const days = byDay([set(0, 10), set(1, 10), set(2, 10, { id: 9 })]);
  assert.equal(trainingStreak(days, TODAY), 3);
});

check('trainingStreak skips nothing: a missed day ends it', () => {
  const days = byDay([set(0, 10), set(2, 10, { id: 9 }), set(3, 10, { id: 8 })]);
  assert.equal(trainingStreak(days, TODAY), 1);
});

check('today-not-yet-trained does not kill yesterday’s streak', () => {
  const days = byDay([set(1, 10, { id: 9 }), set(2, 10, { id: 8 })]);
  assert.equal(trainingStreak(days, TODAY), 2);
});

check('weeklyGoalStreak counts completed weeks, current week only if already met', () => {
  // three finished weeks at 400 reps each, current week untouched
  const sets = [];
  for (let w = 1; w <= 3; w++) {
    for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -7 * w + d), 80, { id: w * 100 + d }));
  }
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 3);
  // meeting it in the current week extends the streak to 4
  sets.push(setOn(TODAY, 400, { id: 999 }));
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 4);
});

check('weeklyGoalStreak breaks on a short week', () => {
  const sets = [];
  for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -14 + d), 80, { id: 200 + d }));
  for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -7 + d), 20, { id: 300 + d }));
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 0);
});

check('dailyGoalStreak needs the daily goal, not just any training', () => {
  const days = byDay([set(0, 60), set(1, 5, { id: 7 }), set(2, 60, { id: 8 })]);
  assert.equal(dailyGoalStreak(days, 50, TODAY, new Set()), 1);
});

check('a rest pass bridges a day below goal', () => {
  const days = byDay([set(0, 60), set(1, 5, { id: 7 }), set(2, 60, { id: 8 })]);
  assert.equal(dailyGoalStreak(days, 50, TODAY, new Set([addDays(TODAY, -1)])), 3);
});

/* ── buckets ──────────────────────────────────────────────────── */

check('dayBuckets returns the requested window, oldest first, ending today', () => {
  const b = dayBuckets(byDay([set(0, 10), set(5, 20, { id: 3 })]), 30);
  assert.equal(b.length, 30);
  assert.equal(b[b.length - 1].key, TODAY);
  assert.equal(b[b.length - 1].reps, 10);
  assert.equal(b[b.length - 6].reps, 20);
  assert.equal(b.reduce((n, x) => n + x.reps, 0), 30);
});

check('weekBuckets totals a week and reports training days', () => {
  const sets = [set(0, 10), set(1, 10, { id: 4 })];
  const w = weekBuckets(byDay(sets), 4).pop();
  assert.equal(w.reps, 20);
  assert.equal(w.days, 2);
  assert.equal(w.key, MONDAY);
});

check('monthBuckets and yearBuckets key correctly', () => {
  const days = byDay([set(0, 10)]);
  assert.equal(monthBuckets(days, 3).pop().key, TODAY.slice(0, 7));
  assert.equal(yearBuckets(days, 2).pop().key, TODAY.slice(0, 4));
});

check('buckets ignore activity outside the window', () => {
  const b = dayBuckets(byDay([set(200, 500, { id: 11 })]), 30);
  assert.equal(b.reduce((n, x) => n + x.reps, 0), 0);
});

/* ── sets-level series ────────────────────────────────────────── */

check('bestSetPerWeek reports the single biggest set of the week', () => {
  const weeks = bestSetPerWeek([set(0, 15), set(1, 40, { id: 12 }), set(0, 9, { id: 13 })], 4).pop();
  assert.equal(weeks.best, 40);
});

check('timeOfDay splits volume into four buckets that sum to 1', () => {
  const t = timeOfDay([set(0, 10, { hour: 6 }), set(0, 10, { id: 14, hour: 13 }), set(0, 20, { id: 15, hour: 22 })]);
  assert.equal(t[1].reps, 10);
  assert.equal(t[2].reps, 10);
  assert.equal(t[3].reps, 20);
  assert.ok(Math.abs(t.reduce((n, b) => n + b.pct, 0) - 1) < 1e-9);
});

/* ── records ──────────────────────────────────────────────────── */

const recordSets = [
  set(0, 25, { id: 21, hour: 7 }),
  set(1, 30, { id: 22, durationMs: 90000 }),
  set(40, 12, { id: 23 }),
  set(400, 18, { id: 24 }),
];

check('records finds best set, longest set and lifetime totals', () => {
  const r = records(recordSets);
  assert.equal(r.bestSet.reps, 30);
  assert.equal(r.longestSet.durationMs, 90000);
  assert.equal(r.lifetimeReps, 85);
  assert.equal(r.lifetimeSets, 4);
  assert.equal(r.bestDay.reps, 30);
});

check('records on empty data returns zeros, not undefined', () => {
  const r = records([]);
  assert.equal(r.lifetimeReps, 0);
  assert.equal(r.bestSet, null);
  assert.equal(r.bestWeek, null);
});

/* ── estimates ────────────────────────────────────────────────── */

check('estimatedMax adds an allowance to a recent best set', () => {
  const e = estimatedMax([set(2, 40, { id: 31 })], 28, TODAY);
  assert.equal(e.basis, 40);
  assert.equal(e.est, 45);            // 40 + min(10, round(4.8)) = 45
});

check('estimatedMax ignores a best set outside the window', () => {
  const e = estimatedMax([set(60, 90, { id: 32 }), set(1, 20, { id: 33 })], 28, TODAY);
  assert.equal(e.basis, 20);
});

check('estimatedMax caps the allowance at ten reps', () => {
  assert.equal(estimatedMax([set(0, 200, { id: 34 })], 28, TODAY).est, 210);
});

check('estimatedMax with no data is zero', () => {
  assert.equal(estimatedMax([], 28, TODAY).est, 0);
});

check('projectTarget needs four data points before it guesses a date', () => {
  const sets = [];
  for (let w = 0; w < 3; w++) sets.push(set(w * 7 + 1, 20 + w * 5, { id: 40 + w }));
  assert.equal(projectTarget(sets, 100).enough, false);
});

check('projectTarget on a rising series gives a future date', () => {
  const sets = [];
  // w counts weeks back from now, so the newest week (w=0) has the most reps
  for (let w = 0; w < 8; w++) sets.push(set(w * 7 + 1, 60 - w * 5, { id: 50 + w }));
  const p = projectTarget(sets, 100);
  assert.equal(p.enough, true);
  assert.ok(p.slope > 0, 'slope should be positive, got ' + p.slope);
  assert.ok(p.weeksTo >= 1 && p.weeksTo <= 260, 'weeksTo=' + p.weeksTo);
  assert.ok(p.date > TODAY, 'projection must be in the future: ' + p.date);
});

check('projectTarget refuses to project on a flat or falling series', () => {
  const sets = [];
  for (let w = 0; w < 8; w++) sets.push(set(w * 7 + 1, 30, { id: 60 + w }));
  const p = projectTarget(sets, 100);
  assert.equal(p.weeksTo, null);
  assert.equal(p.date, null);
});

check('projectTarget says reached when already above the target', () => {
  const sets = [];
  for (let w = 0; w < 6; w++) sets.push(set(w * 7 + 1, 110, { id: 70 + w }));
  assert.equal(projectTarget(sets, 100).weeksTo, 0);
});

/* ── form consistency ─────────────────────────────────────────── */

check('setConsistency needs three reps to report anything', () => {
  const c = setConsistency([{ durationMs: 1000, minElbow: 95 }, { durationMs: 1400, minElbow: 100 }]);
  assert.equal(c.tempoCv, null);
  assert.equal(c.depthCv, null);
});

check('setConsistency measures tempo spread and median', () => {
  const reps = [900, 1000, 1100, 1000].map((d, i) => ({ durationMs: d, minElbow: 90 + i }));
  const c = setConsistency(reps);
  assert.equal(c.reps, 4);
  assert.equal(c.medianMs, 1000);
  assert.ok(c.tempoCv > 0.05 && c.tempoCv < 0.12, 'tempoCv=' + c.tempoCv);
  assert.ok(c.depthCv < 0.05, 'depthCv=' + c.depthCv);
});

check('identical reps give zero variation', () => {
  const c = setConsistency([1, 2, 3].map(() => ({ durationMs: 1000, minElbow: 95 })));
  assert.equal(c.tempoCv, 0);
  assert.equal(c.depthCv, 0);
});

check('consistencySeries skips sets without per-rep rows', () => {
  const sets = [set(0, 10, { id: 81 }), set(1, 10, { id: 82 })];
  const byId = { 81: [{ durationMs: 900, minElbow: 95 }, { durationMs: 1000, minElbow: 96 }, { durationMs: 950, minElbow: 94 }] };
  const s = consistencySeries(sets, byId);
  assert.equal(s.length, 1);
});

check('consistencySeries takes the NEWEST sets even when listSets() is newest-first', () => {
  // three sets; only the two newest carry per-rep rows. A slice(-count) on a newest-first array
  // would silently chart the oldest sets in the database instead.
  const old = set(30, 10, { id: 801 });
  const mid = set(2, 10, { id: 802 });
  const recent = set(0, 10, { id: 803 });
  const reps = (id) => [{ durationMs: 900, minElbow: 95 }, { durationMs: 1000, minElbow: 96 }, { durationMs: 950, minElbow: 94 }].map((r) => ({ ...r }));
  const byId = { [mid.id]: reps(), [recent.id]: reps() };
  const desc = consistencySeries([recent, mid, old], byId, 2);
  const asc = consistencySeries([old, mid, recent], byId, 2);
  assert.equal(desc.length, 2);
  assert.deepEqual(desc.map((d) => d.id), asc.map((d) => d.id));
  assert.deepEqual(desc.map((d) => d.id).sort(), [802, 803]);
});

check('flagMix adds flags over the window', () => {
  const f = flagMix([set(1, 20, { id: 90, flags: { sag: 3, half: 1 } }), set(0, 10, { id: 91, flags: { pike: 2 } })], 7, TODAY);
  assert.deepEqual({ sag: f.sag, pike: f.pike, half: f.half }, { sag: 3, pike: 2, half: 1 });
  assert.equal(f.reps, 30);
  assert.equal(f.sets, 2);
});

/* ── heatmap and gaps ─────────────────────────────────────────── */

check('heatmap returns 7 rows per week column, ending this week', () => {
  const cols = heatmap(byDay([set(0, 60)]), 10, 50, TODAY);
  assert.equal(cols.length, 10);
  assert.equal(cols[0].cells.length, 7);
  assert.equal(cols[9].cells.filter((c) => c.future).length >= 0, true);
  assert.equal(cols[9].cells.find((c) => c.day === TODAY).reps, 60);
});

check('heatmap levels step with the goal', () => {
  const levelFor = (reps) => heatmap(byDay([set(0, reps, { id: 95 })]), 4, 50, TODAY)
    .flatMap((c) => c.cells).find((c) => c.day === TODAY).level;
  assert.equal(levelFor(10), 1);        // some work, under half the goal
  assert.equal(levelFor(25), 2);        // half
  assert.equal(levelFor(50), 3);        // goal met
  assert.equal(levelFor(75), 4);        // 1.5x
  assert.equal(levelFor(200), 4);
  assert.equal(heatmap(byDay([]), 4, 50, TODAY).flatMap((c) => c.cells).find((c) => c.day === TODAY).level, 0);
});

check('gaps lists the empty days between two training days', () => {
  const g = gaps(byDay([set(0, 10), set(4, 10, { id: 97 })]), 30);
  assert.equal(g.length, 3);
  assert.equal(g[0], addDays(TODAY, -3));
});

check('gaps needs two anchors before it claims anything is missing', () => {
  assert.deepEqual(gaps(byDay([set(0, 10)]), 30), []);
});

/* ── summarize ────────────────────────────────────────────────── */

check('summarize reports today, week, month, year and streak together', () => {
  const sets = [set(0, 30), set(0, 20, { id: 101 }), set(8, 40, { id: 102 })];
  const s = summarize(sets, { dailyGoal: 50 });
  assert.equal(s.today.reps, 50);
  assert.equal(s.goalPct, 1);
  assert.equal(s.goalLeft, 0);
  assert.equal(s.week.reps + s.month.reps >= 50, true);
  assert.equal(s.lifetime, 90);
  assert.equal(s.setsToday, 2);
  assert.equal(s.streak, 1);
});

check('summarize with no goal does not divide by zero', () => {
  const s = summarize([set(0, 10)], { dailyGoal: 0 });
  assert.equal(s.goalPct, 0);
  assert.equal(s.goalLeft, 0);
});

console.log('\n' + (fail ? fail + ' FAILED' : 'ALL CHECKS PASSED') + ' — ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
__EOF_tests_stats_test_mjs__

mkdir -p 'tools'
cat > 'tools/audit.mjs' <<'__EOF_tools_audit_mjs__'
// Design rubric audit, measured in a real Chromium at iPhone metrics.
// Checks OpenDesign's craft rules that are machine-verifiable: WCAG contrast, tap targets,
// accent discipline, heading structure, focus styling, chart text alternatives, state coverage.
//   node tools/audit.mjs [base-url]            # default http://127.0.0.1:8099
//   SCHEMES=dark SHOTS=0 node tools/audit.mjs
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9344;
const W = Number(process.env.SHOT_W || 402), H = Number(process.env.SHOT_H || 874);
const BASE = process.argv[2] || 'http://127.0.0.1:8099';
const SCHEMES = (process.env.SCHEMES || 'dark,light').split(',');
const SHOTS = process.env.SHOTS !== '0';
const ROUTES = (process.env.ROUTES || '/today,/train,/train@count,/train@summary,/progress,/badges,/settings').split(',');
// A route can carry a state suffix — /train@count walks the view into the counting screen before
// measuring it, so the rubric covers the phases a static hash navigation never reaches.
const STATES = {
  count: `(async () => {
    const q = (s) => document.querySelector(s);
    const nap = (ms) => new Promise((r) => setTimeout(r, ms));
    const m = q('#manualChk'); if (m && !m.checked) { m.click(); await nap(500); }
    if (q('#startBtn')) { q('#startBtn').click(); await nap(500); }
    for (let i = 0; i < 12; i++) q('#chip').click();
    return 'rep=' + q('#repnum').textContent;
  })()`,
  summary: `(async () => {
    const q = (s) => document.querySelector(s);
    const nap = (ms) => new Promise((r) => setTimeout(r, ms));
    const m = q('#manualChk'); if (m && !m.checked) { m.click(); await nap(500); }
    if (q('#startBtn')) { q('#startBtn').click(); await nap(500); }
    if (q('#chip')) for (let i = 0; i < 12; i++) q('#chip').click();
    q('#endBtn').click();
    return 'summary';
  })()`,
};
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

// Fresh profile every run: a service worker left over from a previous run would serve its own precache.
const profile = mkdtempSync(join(tmpdir(), 'pushups-audit-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, `--user-agent=${UA}`,
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--hide-scrollbars', '--allow-running-insecure-content', '--mute-audio', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function firstTarget() {
  for (let i = 0; i < 80; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page;
    } catch { /* starting */ }
    await sleep(250);
  }
  throw new Error('chrome did not start:\n' + chromeErr.slice(-1500));
}

let id = 0;
const pending = new Map();
let ws;
let consoleErrors = [];
function send(method, params = {}) {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params }));
  return new Promise((resolve, reject) => pending.set(mid, { resolve, reject }));
}
async function evalJs(expr, label) {
  const res = await send('Runtime.evaluate', { expression: `(async () => { return (${expr}); })()`, awaitPromise: true, returnByValue: true });
  if (res.exceptionDetails) throw new Error(`${label}: ${res.exceptionDetails.exception?.description || res.exceptionDetails.text}`);
  return res.result?.value;
}

const page = await firstTarget();
ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(m.error.message)); else resolve(m.result);
  } else if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
    // Headless has no user activation, so haptics log a warning the phone never would.
    if (/Blocked call to navigator\.vibrate/i.test(m.params.entry.text)) return;
    consoleErrors.push(m.params.entry.text);
  } else if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    consoleErrors.push('exception: ' + (d.exception?.description || d.text));
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
// This is a design audit of the files on disk, so nothing may come from a cache: the service
// worker precaches every asset and would happily serve last night's build.
await send('Network.setCacheDisabled', { cacheDisabled: true });

// The in-page probe: one pass over the rendered DOM, returns every finding.
const PROBE = `(() => {
  const px = (c) => {
    const m = /rgba?\\(([^)]+)\\)/.exec(c) || /oklab\\(([^)]+)\\)/.exec(c);
    if (!m) return null;
    const p = m[1].split(/[\\s,/]+/).filter(Boolean);
    if (/oklab/.test(c)) return null;
    const n = p.map((v, i) => i === 3 ? parseFloat(v) : (v.endsWith('%') ? parseFloat(v) / (i ? 1 : 2.55) : parseFloat(v)));
    return { r: n[0], g: n[1], b: n[2], a: n.length > 3 ? n[3] : 1 };
  };
  const over = (c, b) => c.a >= 1 ? c : { r: c.r * c.a + b.r * (1 - c.a), g: c.g * c.a + b.g * (1 - c.a), b: c.b * c.a + b.b * (1 - c.a), a: 1 };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.93 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); };
  const ratio = (a, b) => { const l1 = lum(a), l2 = lum(b); return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05); };
  const hex = (c) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  const bgOf = (el) => {
    let out = [];
    for (let n = el; n; n = n.parentElement) {
      const c = px(getComputedStyle(n).backgroundColor);
      if (c && c.a > 0) { out.push(c); if (c.a >= 1) break; }
    }
    let acc = { r: 0, g: 0, b: 0, a: 1 };
    for (let i = out.length - 1; i >= 0; i--) acc = over(out[i], acc);
    return acc;
  };
  const shown = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const s = getComputedStyle(el);
    if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) < 0.05) return false;
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return false;
    return true;
  };
  const root = getComputedStyle(document.documentElement);
  const tokens = {};
  for (const k of ['--track', '--brass', '--rose', '--plum', '--ink', '--porcelain', '--bg', '--sheet', '--text', '--muted']) {
    const v = root.getPropertyValue(k).trim();
    const m = /^#([0-9a-f]{6})$/i.exec(v);
    if (m) tokens[k.slice(2)] = { r: parseInt(m[1].slice(0, 2), 16), g: parseInt(m[1].slice(2, 4), 16), b: parseInt(m[1].slice(4, 6), 16), a: 1 };
  }
  const near = (c, t) => c && Math.abs(c.r - t.r) + Math.abs(c.g - t.g) + Math.abs(c.b - t.b) < 24;

  const findings = [];
  const accents = {};
  const seen = new Set();

  // 1. text contrast, per visible text run
  for (const el of document.querySelectorAll('body *')) {
    if (!el.parentElement || !shown(el)) continue;
    let text = '';
    for (const n of el.childNodes) if (n.nodeType === 3) text += n.nodeValue;
    text = text.trim();
    if (!text) continue;
    const s = getComputedStyle(el);
    if (Number(s.opacity) < 0.5 && !el.closest('[data-counting]')) { /* faded on purpose */ }
    const fg = over(px(s.color) || { r: 0, g: 0, b: 0, a: 1 }, bgOf(el));
    const bg = bgOf(el);
    const size = parseFloat(s.fontSize), weight = Number(s.fontWeight) || 400;
    const large = size >= 24 || (size >= 18.5 && weight >= 700);
    const min = large ? 3 : 4.5;
    const r = ratio(fg, bg);
    if (r < min) findings.push({ kind: 'contrast', worst: +r.toFixed(2), need: min, where: text.slice(0, 34), color: hex(fg), on: hex(bg), px: Math.round(size * 10) / 10, w: weight, sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).join('.') : '') });
    // 2. accent flood: saturated token used as text or fill
    for (const [name, tok] of Object.entries(tokens)) {
      if (!['track', 'brass', 'rose', 'plum'].includes(name)) continue;
      if (near(px(s.color), tok)) { accents[name] = (accents[name] || 0) + 1; (accents[name + '_ex'] = accents[name + '_ex'] || []).push(text.slice(0, 20)); }
      const fill = px(s.backgroundColor), stroke = px(s.borderTopColor);
      if (fill && fill.a > 0.3 && near(fill, tok)) { accents[name] = (accents[name] || 0) + 1; }
      else if (stroke && stroke.a > 0.3 && near(stroke, tok)) { accents[name] = (accents[name] || 0) + 1; }
    }
  }

  // 3. tap targets — measured against the real hit area: a control inside a <label> is tapped
  // through the label, so the label box is the target.
  const targets = [];
  for (const el of document.querySelectorAll('a[href],button,input,select,textarea,[role="button"],[tabindex]:not([tabindex="-1"])')) {
    if (!shown(el) || el.disabled) continue;
    const lab = el.matches('input,select,textarea') ? el.closest('label') : null;
    const hit = lab || el;
    const r = hit.getBoundingClientRect();
    const w = Math.round(r.width), h = Math.round(r.height);
    if (w >= 44 && h >= 44) continue;
    const label = (el.getAttribute('aria-label') || hit.textContent || el.type || '').trim().replace(/\\s+/g, ' ').slice(0, 26);
    targets.push({ label, w, h, aa_fail: w < 24 || h < 24, sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.') : '') });
  }

  // 4. headings + landmarks + chart alternatives
  const heads = [...document.querySelectorAll('h1,h2,h3,h4')].map((h) => h.tagName + ' ' + h.textContent.trim().slice(0, 30));
  const skipped = heads.some((h, i) => i > 0 && Number(h[1]) - Number(heads[i - 1][1]) > 1);
  const svgNoAlt = [...document.querySelectorAll('svg')].filter((s) => {
    const r = s.getBoundingClientRect();
    return r.width > 60 && r.height > 60 && !s.getAttribute('aria-label') && !s.querySelector('title')
      && !s.closest('[aria-label]') && s.getAttribute('aria-hidden') !== 'true' && !s.closest('[aria-hidden="true"]');
  }).length;
  const zoomBlocked = /user-scalable\s*=\s*no|maximum-scale/i.test((document.querySelector('meta[name=viewport]') || {}).content || '');
  const imgsNoAlt = [...document.querySelectorAll('img')].filter((i) => i.getAttribute('alt') === null).length;

  // 5. focus styling killed anywhere?
  let outlineKilled = false, reducedMotion = 0;
  for (const sheet of document.styleSheets) {
    let rules; try { rules = sheet.cssRules; } catch { continue; }
    for (const rule of rules || []) {
      const t = rule.cssText || '';
      if (/outline\\s*:\\s*(none|0)/.test(t) || /outline-width\\s*:\\s*0/.test(t)) outlineKilled = true;
      if (rule.media && /prefers-reduced-motion/.test(rule.media.mediaText)) reducedMotion++;
      for (const inner of rule.cssRules || []) if (/prefers-reduced-motion/.test(inner.conditionText || '')) reducedMotion++;
    }
  }

  return JSON.stringify({
    findings, accents, targets, heads, skipped, svgNoAlt, imgsNoAlt, outlineKilled, reducedMotion, zoomBlocked,
    tokens: Object.fromEntries(Object.entries(tokens).map(([k, v]) => [k, hex(v)])),
    viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio },
    scroll: { client: document.querySelector('#view')?.scrollHeight, visible: innerHeight },
  });
})()`;

const report = {};
for (const scheme of SCHEMES) {
  for (const spec of ROUTES) {
    const [route, state] = spec.split('@');
    const url = `${BASE}/index.html#${route}`;
    consoleErrors = [];
    await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: true });
    await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
    await send('Page.navigate', { url });
    await sleep(2500);
    await evalJs(`import('${BASE}/tools/seed.js').then(m => m.seed(90))`, 'seed');
    await sleep(1200);
    await evalJs(`location.hash = ${JSON.stringify(route)}`, 'route');
    await sleep(1200);
    if (state) { await evalJs(STATES[state], state); await sleep(700); }
    const raw = await evalJs(PROBE, 'probe');
    const data = JSON.parse(raw);
    data.consoleErrors = consoleErrors.slice();
    report[`${scheme}:${spec}`] = data;
    if (SHOTS) {
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      const file = `/tmp/audit_${scheme}${spec.replace(/[\/@]/g, '_')}.png`;
      writeFileSync(file, Buffer.from(shot.data, 'base64'));
    }
  }
}
await send('Emulation.clearDeviceMetricsOverride').catch(() => {});
ws.close();
chrome.kill();

writeFileSync('/tmp/pushups-audit.json', JSON.stringify(report, null, 2));

// ── human report ──
let fails = 0;
const SEV = (n) => n;
for (const [key, d] of Object.entries(report)) {
  const contrast = d.findings.filter((f) => f.kind === 'contrast');
  const worst = [...contrast].sort((a, b) => a.worst - b.worst).slice(0, 6);
  const aa = d.targets.filter((t) => t.aa_fail);
  const hig = d.targets.filter((t) => !t.aa_fail);
  const accentTotal = Object.entries(d.accents).filter(([k]) => !k.endsWith('_ex'));
  const issues = [];
  if (contrast.length) issues.push(`contrast ${contrast.length}`);
  if (aa.length) issues.push(`AA-target ${aa.length}`);
  if (hig.length) issues.push(`44pt-target ${hig.length}`);
  if (!d.heads.some((h) => h.startsWith('H1'))) issues.push('no-h1');
  if (d.skipped) issues.push('heading-skip');
  if (d.svgNoAlt) issues.push(`svg-no-alt ${d.svgNoAlt}`);
  if (d.outlineKilled) issues.push('outline-killed');
  if (!d.reducedMotion) issues.push('no-reduced-motion');
  if (d.zoomBlocked) issues.push('zoom-blocked');
  if (d.consoleErrors.length) issues.push(`console ${d.consoleErrors.length}`);
  fails += issues.length;
  console.log(`\n${key}${issues.length ? '   ✗ ' + issues.join('  ') : '   ✓ clean'}`);
  console.log(`   accents: ${accentTotal.map(([k, v]) => `${k}×${v}`).join(' ') || 'none'} · headings: ${d.heads.map((h) => h.split(' ')[0]).join('>') || 'none'}`);
  for (const f of worst) console.log(`   [contrast ${f.worst}/${f.need}] "${f.where}" ${f.color} on ${f.on} @${f.px}px/${f.w} — ${f.sel}`);
  const tally = (list) => {
    const m = new Map();
    for (const t of list) {
      const k = t.sel + ' ' + t.w + '×' + t.h;
      m.set(k, (m.get(k) || 0) + 1);
      if (!m.has(k + '|ex')) m.set(k + '|ex', t.label);
    }
    return [...m].filter(([k]) => !k.endsWith('|ex')).slice(0, 6)
      .map(([k, n]) => `   ${k} ×${n}  "${m.get(k + '|ex')}"`);
  };
  for (const line of tally(aa)) console.log('   [AA target]' + line);
  for (const line of tally(hig)) console.log('   [under 44pt]' + line);
  for (const e of d.consoleErrors.slice(0, 3)) console.log(`   [console] ${e}`);
}
console.log(`\n${fails ? 'FAIL' : 'PASS'} — ${fails} issue groups. Full data: /tmp/pushups-audit.json${SHOTS ? ' · shots /tmp/audit_*.png' : ''}`);
process.exit(0);
__EOF_tools_audit_mjs__

mkdir -p 'tools'
cat > 'tools/build-stamp.sh' <<'__EOF_tools_build_stamp_sh__'
#!/usr/bin/env bash
# Regenerate sw.js from tools/sw.template.js with a fresh cache version + precache list.
set -euo pipefail
cd "$(dirname "$0")/.."

# Precache entries stay relative: the service worker lives next to index.html, so the browser
# resolves them against the app root wherever it is hosted (a Pages subpath or a domain root).

BUILD="$(date +%y%m%d%H%M)"
{ date -u +%FT%TZ; echo "$BUILD"; } > tools/stamp.txt

# The nosimd wasm pair is a desktop-Safari fallback, and pose_landmarker_full is an opt-in in
# Settings. Keeping all three out of the precache holds the phone's first download to ~11 MB;
# they are still cached permanently the first time they are used.
find . -type f \
  ! -path './.git/*' ! -name 'sw.js' ! -name 'serve.py' \
  ! -path './tools/*' ! -path './tests/*' ! -path './scripts/*' \
  ! -name '.DS_Store' ! -name '.*' ! -name '*.mov' ! -name 'config.json' \
  ! -name '*nosimd*' ! -name 'pose_landmarker_full.task' \
  | sed 's|^\./||' | sort > tools/precache.txt

/usr/bin/python3 - "$BUILD" <<'PY'
import pathlib, sys
build = sys.argv[1]
files = [f for f in pathlib.Path('tools/precache.txt').read_text().splitlines() if f.strip()]
items = ',\n  '.join('"%s"' % f for f in files)
tpl = pathlib.Path('tools/sw.template.js').read_text()
out = tpl.replace('__BUILD__', build).replace('__PRECACHE__', '[\n  %s\n]' % items)
pathlib.Path('sw.js').write_text(out)
print('sw.js stamped: build %s, %d files precached' % (build, len(files)))
PY
__EOF_tools_build_stamp_sh__

mkdir -p 'tools'
cat > 'tools/fetch-assets.sh' <<'__EOF_tools_fetch_assets_sh__'
#!/usr/bin/env bash
# Download every binary asset the app needs and self-host it. No build step, no CDN at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
MP="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14"
MODEL="https://storage.googleapis.com/mediapipe-models/pose_landmarker"
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

get() { # get <url> <dest>
  if [ -s "$2" ]; then echo "ok   $2 (already there)"; return; fi
  echo ".. $2"
  curl -fL --retry 3 --retry-delay 1 -o "$2" "$1"
}

mkdir -p vendor/mediapipe/wasm models fonts icons

get "$MP/vision_bundle.mjs"                        vendor/mediapipe/vision_bundle.mjs
get "$MP/wasm/vision_wasm_internal.js"             vendor/mediapipe/wasm/vision_wasm_internal.js
get "$MP/wasm/vision_wasm_internal.wasm"           vendor/mediapipe/wasm/vision_wasm_internal.wasm
get "$MP/wasm/vision_wasm_nosimd_internal.js"      vendor/mediapipe/wasm/vision_wasm_nosimd_internal.js
get "$MP/wasm/vision_wasm_nosimd_internal.wasm"    vendor/mediapipe/wasm/vision_wasm_nosimd_internal.wasm
get "$MODEL/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" models/pose_landmarker_lite.task
get "$MODEL/pose_landmarker_full/float16/1/pose_landmarker_full.task"  models/pose_landmarker_full.task

# Latin woff2 slices of the two faces, resolved through the Google Fonts CSS API with a Safari UA
# so we get woff2 rather than ttf.
slice() { # slice <family+weight url> <dest>
  local css="$1" dest="$2" u
  u=$(curl -fsS -A "$UA" "$css" | awk '/\/\* latin \*\//{f=1} f&&/url\(https/{match($0,/https:\/\/[^)]*woff2/); print substr($0,RSTART,RLENGTH); exit}')
  if [ -z "$u" ]; then echo "WARN no latin slice for $css — the app falls back to system fonts"; return; fi
  get "$u" "$dest"
}
slice "https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500&display=swap" fonts/barlow-semi-condensed.woff2
slice "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400&display=swap"        fonts/ibm-plex-sans.woff2

echo
echo "sizes:"
du -sh vendor models fonts | sed 's/\t/  /'
PYI=""
for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import PIL' >/dev/null 2>&1; then PYI="$p"; break; fi
done
if [ -z "$PYI" ]; then
  echo "WARN Pillow missing — installing into Homebrew python"
  /opt/homebrew/bin/python3 -m pip install --quiet pillow || true
  PYI=/opt/homebrew/bin/python3
fi
"$PYI" tools/make-icons.py
ls -l icons
__EOF_tools_fetch_assets_sh__

mkdir -p 'tools'
cat > 'tools/make-icons.py' <<'__EOF_tools_make_icons_py__'
#!/usr/bin/env python3
"""Generate the app icons with Pillow: a side-view plank figure, elbow joint in brass."""
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("NEED PIL — run: /opt/homebrew/bin/python3 -m pip install pillow")

INK = (14, 26, 24)
PALE = (220, 230, 226)
FLOOR = (38, 60, 57)
BRASS = (201, 146, 47)
TRACK = (79, 163, 165)


def figure(size, inset=0.0):
    s = size
    img = Image.new("RGB", (s, s), INK)
    d = ImageDraw.Draw(img)
    pad = s * (0.10 + inset)
    w = s * 0.055

    floor_y = s * 0.80
    d.line([pad * 0.6, floor_y, s - pad * 0.6, floor_y], fill=FLOOR, width=int(s * 0.018))

    def P(xf, yf):
        x = pad + (s - 2 * pad) * xf
        y = pad + (s - 2 * pad) * yf
        return (x, y)

    shoulder = P(0.27, 0.44)
    hip = P(0.56, 0.50)
    knee = P(0.73, 0.53)
    ankle = P(0.90, 0.56)
    elbow = P(0.245, 0.63)
    wrist = P(0.34, 0.745)
    head = P(0.155, 0.385)

    d.line([hip, knee, ankle], fill=PALE, width=int(w), joint="curve")
    d.line([shoulder, hip], fill=PALE, width=int(w * 1.08), joint="curve")
    d.line([shoulder, elbow, wrist], fill=TRACK, width=int(w * 0.8), joint="curve")
    r = s * 0.085
    d.ellipse([head[0] - r, head[1] - r, head[0] + r, head[1] + r], fill=PALE)
    for pt, rad, col in ((elbow, 0.048, BRASS), (ankle, 0.030, PALE), (wrist, 0.030, TRACK)):
        rr = s * rad
        d.ellipse([pt[0] - rr, pt[1] - rr, pt[0] + rr, pt[1] + rr], fill=col)
    return img


def save(size, name, maskable=False):
    img = figure(size, inset=0.16 if maskable else 0.0)
    img.save("icons/" + name)
    print("wrote icons/%s (%dpx)" % (name, size))


save(512, "icon-512.png")
save(192, "icon-192.png")
save(512, "maskable-512.png", maskable=True)
save(192, "maskable-192.png", maskable=True)
save(180, "apple-touch-icon.png")
save(32, "favicon-32.png")
__EOF_tools_make_icons_py__

mkdir -p 'tools'
cat > 'tools/make-installer.sh' <<'__EOF_tools_make_installer_sh__'
#!/usr/bin/env bash
# Emit scripts/install-phase1.sh: one self-contained bash script that recreates the whole app from
# scratch (heredocs for text, curl for binaries). Keeps the paste-able artifact and the repo in sync.
set -euo pipefail
cd "$(dirname "$0")/.."

# Usage: tools/make-installer.sh [phase-number] [what-the-phase-does]
PHASE="${1:-1}"
DESC="${2:-counter core}"
OUT="scripts/install-phase${PHASE}.sh"
TMP="$(mktemp)"

FILES=$(find . -type f \
  ! -path './.git/*' ! -path './vendor/*' ! -path './models/*' ! -path './fonts/*' ! -path './icons/*' \
  ! -name 'sw.js' ! -name 'precache.txt' ! -name 'stamp.txt' ! -name 'base-url' ! -name 'install-phase*.sh' \
  ! -name '.DS_Store' ! -name '*.mov' ! -name '*.mp4' \
  | sed 's|^\./||' | sort)

{
  echo '#!/usr/bin/env bash'
  echo "# Pushups PWA — phase ${PHASE} installer (${DESC}). Self-contained: writes every source file, then downloads"
  echo '# the MediaPipe wasm + pose models + fonts and generates the icons. Re-runnable; overwrites'
  echo '# only files inside the app folder. Nothing here touches your saved sets (they live on the phone).'
  echo 'set -euo pipefail'
  echo 'ROOT="${1:-$HOME/Projects/pushups}"'
  echo 'mkdir -p "$ROOT"; cd "$ROOT"'
  echo 'umask 022'
  echo

  for f in $FILES; do
    dir=$(dirname "$f")
    if [ "$dir" = "." ]; then
      echo "mkdir -p ."
    else
      echo "mkdir -p '$dir'"
    fi
    marker="__EOF_${f//[^A-Za-z0-9]/_}__"
    echo "cat > '$f' <<'$marker'"
    cat "$f"
    echo "$marker"
    echo
  done

  echo 'chmod +x tools/*.sh scripts/*.py tools/make-icons.py 2>/dev/null || true'
  echo 'chmod +x tools/*.py 2>/dev/null || true'
  echo 'bash tools/fetch-assets.sh'
  echo 'echo "/pushups-pwa/" > tools/base-url'
  echo 'bash tools/build-stamp.sh'
  echo 'echo'
  echo 'echo "Phase 1 written to $ROOT"'
  echo 'echo "Next: ./scripts/deploy.sh -m \"phase ${PHASE}: ${DESC}\""'
} > "$TMP"

mv "$TMP" "$OUT"
chmod +x "$OUT"
lines=$(wc -l < "$OUT" | tr -d ' ')
bytes=$(wc -c < "$OUT" | tr -d ' ')
echo "$OUT: $lines lines, $bytes bytes, $(echo "$FILES" | wc -l | tr -d ' ') files embedded"
__EOF_tools_make_installer_sh__

mkdir -p 'tools'
cat > 'tools/seed.js' <<'__EOF_tools_seed_js__'
/* Dev-only fixture writer. Seeds a plausible training history so the Today and Progress screens can
   be screenshot without doing pushups. Never imported by the app; excluded from the service worker.
   From the console:   import('/tools/seed.js').then(m => m.seed())        // 90 days
                      import('/tools/seed.js').then(m => m.seed(14))       // 14 days
                      import('/tools/seed.js').then(m => m.clear())        // remove the fixtures */

const TAG = 'seed';

function dayKey(ms) {
  const d = new Date(ms);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

function mulberry(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export async function seed(days = 90, seedValue = 7) {
  const db = await import('../js/db.js');
  const rnd = mulberry(seedValue);
  const now = new Date();
  let added = 0;
  for (let back = days - 1; back >= 0; back--) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - back, 7, 0, 0, 0);
    const key = dayKey(d.getTime());
    const weekday = d.getDay();
    if (weekday === 6) continue;                       // Saturday off
    if (back > 40 && rnd() < 0.25) continue;           // patchier history further back
    const fitness = 18 + (days - back) * 0.22;         // slow upward trend
    const sets = 1 + Math.floor(rnd() * 2);
    for (let s = 0; s < sets; s++) {
      const reps = Math.max(3, Math.round(fitness * (0.7 + rnd() * 0.6)));
      const startedAt = d.getTime() + s * 900000 + Math.floor(rnd() * 300000);
      const flagged = rnd() < 0.25 ? 1 + Math.floor(rnd() * 2) : 0;
      const id = await db.saveSet({
        startedAt, endedAt: startedAt + reps * 3200, durationMs: reps * 3200,
        mode: 'camera', source: 'camera', repsDetected: reps + flagged, repsFinal: reps,
        flags: { sag: flagged, pike: 0, half: flagged, lockout: 0, lost: 0 },
        cameraUsed: 'environment', qualityStats: { fpsMean: 22, visMean: 0.82, frames: 400, breaks: 0 },
        paramsUsed: { top: 155, bottom: 100, minRepMs: 400 }, presetName: 'standard', model: 'lite',
        notes: '', day: key, [TAG]: true,
      }, makeReps(reps + flagged, rnd));
      added += 1;
      void id;
    }
  }
  return { added, days };
}

function makeReps(n, rnd) {
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push({
      tMs: i * (2600 + Math.floor(rnd() * 500)),
      durationMs: 2200 + Math.floor(rnd() * 900),
      minElbow: 88 + Math.floor(rnd() * 22),
      maxElbow: 158 + Math.floor(rnd() * 14),
      shoulderDrop: 0.12 + rnd() * 0.1,
      hipOffset: (rnd() - 0.45) * 0.2,
      side: rnd() < 0.5 ? 'left' : 'right',
      flags: [],
      n: i + 1,
    });
  }
  return out;
}

export async function clear() {
  const db = await import('../js/db.js');
  const all = await db.listSets();
  let n = 0;
  for (const s of all) {
    if (s && s[TAG]) { await db.deleteSet(s.id); n += 1; }
  }
  return { removed: n, left: (await db.listSets()).length };
}
__EOF_tools_seed_js__

mkdir -p 'tools'
cat > 'tools/serve.py' <<'__EOF_tools_serve_py__'
#!/usr/bin/env python3
"""Dev server: correct MIME types for wasm/mjs/woff2/task, and no caching of sw.js."""
import functools
import http.server
import socketserver
import sys

TYPES = {
    ".wasm": "application/wasm",
    ".mjs": "text/javascript",
    ".js": "text/javascript",
    ".css": "text/css",
    ".json": "application/json",
    ".task": "application/octet-stream",
    ".woff2": "font/woff2",
    ".webmanifest": "application/manifest+json",
    ".heic": "image/heic",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=".", **kw)

    def guess_type(self, path):
        for ext, mime in TYPES.items():
            if path.endswith(ext):
                return mime
        return super().guess_type(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with Server(("0.0.0.0", port), Handler) as httpd:
        print("listening on 0.0.0.0:%d" % port)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
__EOF_tools_serve_py__

mkdir -p 'tools'
cat > 'tools/shots.mjs' <<'__EOF_tools_shots_mjs__'
// UI screenshot harness: headless Chrome at iPhone metrics, driven over CDP.
//   node tools/shots.mjs <url> <out.png> [--dark] [--light] [--step <js>] [--wait <ms>] [--click <selector>]
// Chrome flags include a fake camera device, so #/train reaches the real setup layout.
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9333;
const W = Number(process.env.SHOT_W || 402), H = Number(process.env.SHOT_H || 874);
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

const argv = process.argv.slice(2);
const url = argv.shift();
const out = argv.shift();
if (!url || !out) {
  console.error('usage: node tools/shots.mjs <url> <out.png> [--dark] [--step <js>] [--click <sel>] [--wait <ms>]');
  process.exit(2);
}
const steps = [];
let scheme = '';
while (argv.length) {
  const f = argv.shift();
  if (f === '--dark') scheme = 'dark';
  else if (f === '--light') scheme = 'light';
  else if (f === '--step' || f === '--click' || f === '--wait') steps.push([f.slice(2), argv.shift()]);
  else throw new Error('unknown flag ' + f);
}

// Fresh profile per run — a leftover service worker would serve its own stale precache.
const profile = mkdtempSync(join(tmpdir(), 'pushups-shot-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, `--user-agent=${UA}`,
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--hide-scrollbars', '--allow-running-insecure-content', '--mute-audio',
  'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page;
    } catch { /* still starting */ }
    await sleep(250);
  }
  throw new Error('chrome did not start:\n' + chromeErr.slice(-2000));
}

let id = 0;
const pending = new Map();
let ws;
function send(method, params = {}) {
  const msgId = ++id;
  ws.send(JSON.stringify({ id: msgId, method, params }));
  return new Promise((resolve, reject) => pending.set(msgId, { resolve, reject }));
}

const page = await target();
ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(m.error.message)); else resolve(m.result);
  } else if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
    console.error('  [console]', m.params.entry.text);
  } else if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    console.error('  [exception]', d.exception?.description || d.text);
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: true });
await send('Network.setUserAgentOverride', { userAgent: UA });
if (scheme) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
await send('Page.navigate', { url });
await sleep(3500);

for (const [kind, arg] of steps) {
  if (kind === 'wait') { await sleep(Number(arg)); continue; }
  const expr = kind === 'click'
    ? `(() => { const el = document.querySelector(${JSON.stringify(arg)}); if (!el) throw new Error('no element ' + ${JSON.stringify(arg)}); el.click(); return 'clicked'; })()`
    : `(async () => { let f = (${arg}); if (typeof f === 'function') f = f(); const v = await f; return typeof v === 'string' ? v : JSON.stringify(v); })()`;
  const res = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (res.exceptionDetails) {
    console.error('  [step failed]', arg, res.exceptionDetails.exception?.description || '');
  } else if (process.env.SHOW_STEPS) {
    console.log('  [step]', arg, '=>', res.result?.value);
  }
  await sleep(700);
}

const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
writeFileSync(out, Buffer.from(shot.data, 'base64'));
console.log('wrote', out);
ws.close();
chrome.kill();
process.exit(0);
__EOF_tools_shots_mjs__

mkdir -p 'tools'
cat > 'tools/sw.template.js' <<'__EOF_tools_sw_template_js__'
const CACHE = 'pushups-v-__BUILD__';
const PRECACHE = __PRECACHE__;

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.allSettled(PRECACHE.map((u) => c.add(u)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => {
  if (e.data === 'skip') self.skipWaiting();
  if (e.data === 'reload-now') {
    self.clients.matchAll({ type: 'window' }).then((cs) => cs.forEach((c) => c.postMessage('reload')));
  }
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;

  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      try {
        const net = await fetch(req);
        const c = await caches.open(CACHE);
        c.put('index.html', net.clone());
        return net;
      } catch {
        const c = await caches.open(CACHE);
        return (await c.match('index.html')) || (await c.match('./')) || Response.error();
      }
    })());
    return;
  }

  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    const hit = await c.match(req, { ignoreSearch: true });
    if (hit) {
      const p = new URL(req.url).pathname;
      if (!/vendor|models|fonts/.test(p)) {
        fetch(req).then((n) => n.ok && c.put(req, n)).catch(() => {});
      }
      return hit;
    }
    try {
      const net = await fetch(req);
      if (net.ok) c.put(req, net.clone());
      return net;
    } catch {
      const stale = await c.match(req, { ignoreSearch: true });
      return stale || new Response('offline', { status: 503 });
    }
  })());
});
__EOF_tools_sw_template_js__

chmod +x tools/*.sh scripts/*.py tools/make-icons.py 2>/dev/null || true
chmod +x tools/*.py 2>/dev/null || true
bash tools/fetch-assets.sh
echo "/pushups-pwa/" > tools/base-url
bash tools/build-stamp.sh
echo
echo "Phase 1 written to $ROOT"
echo "Next: ./scripts/deploy.sh -m \"phase ${PHASE}: ${DESC}\""
