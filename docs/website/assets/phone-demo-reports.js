/* DeuceMate iPhone demo: interactive match reports and trends.
   The report is a browser-side approximation of MatchDetailView and
   PointsGraphView. Archive data and device services are simulated. */
(function () {
  "use strict";
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function safe(value) { return String(value == null ? "" : value); }
  function other(p) { return p === "me" ? "opponent" : "me"; }
  function labelOutcome(x) { return ({ winner: "Winner", forcedError: "Forced error", unforcedError: "Unforced error", doubleFault: "Double fault", uncategorized: "Uncategorised" })[x] || "Point"; }
  function labelShot(x) { return ({ serve: "Serve / ace", return: "Return", servePlusOne: "Serve +1", rally: "Rally" })[x] || "—"; }
  function percent(n, d) { return d ? Math.round(n * 100 / d) + "%" : "—"; }
  function matchResult(r,focal) { if(r.iWon==null)return r.endTime?"Draw":"In progress";var won=focal==="opponent"?!r.iWon:r.iWon;return won?"Won":"Lost"; }
  function fmtDate(ms) { return new Date(ms).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }); }
  function detailTitle(record) {
    if (record.endTime == null) return fmtDate(record.startTime);
    var formats = { superTiebreak: "Super Tiebreak", perpetualSuperTiebreak: "Perpetual Tiebreak", quick4Games: "Quick 4 Games", perpetualPoints: "Perpetual Points" };
    if (formats[record.format]) return formats[record.format];
    return (record.stats || []).some(function (point) { return point.outcome !== "uncategorized"; }) ? "Match Stats" : "Score Only Match";
  }
  function fmtDuration(seconds) { var s = Math.max(0, Number(seconds) || 0); return Math.floor(s / 60) + " min"; }
  function fmtFormat(r) { var shell=window.DeuceMateShell,info=shell&&shell.formatInfo?shell.formatInfo(r.format):null;return (info?info.label:(r.format||"Best of 3"))+" · "+(r.matchType==="doubles"?"Doubles":"Singles"); }
  function setLabel(r,s,index,focal) {
    var engine=window.DeuceMateScoring,cfg=engine&&engine.cfgFor?engine.cfgFor(r.format||"standard"):null;
    var superTB=!!(cfg&&engine.isDecidingSuperTiebreak&&engine.isDecidingSuperTiebreak(cfg,index));
    var me=focal==="opponent"?(s.gamesOpponent||0):(s.gamesMe||0),opp=focal==="opponent"?(s.gamesMe||0):(s.gamesOpponent||0);
    var tm=focal==="opponent"?(s.tieBreakPointsOpponent||0):(s.tieBreakPointsMe||0),to=focal==="opponent"?(s.tieBreakPointsMe||0):(s.tieBreakPointsOpponent||0);
    if((cfg&&!cfg.playRegularSets)||(superTB&&s.isTieBreak))return tm+"–"+to;
    if(s.isTieBreak&&(me+opp>0))return me+"–"+opp+"("+tm+"–"+to+")";
    if(s.isTieBreak)return tm+"–"+to;
    return me+"–"+opp;
  }
  function score(r,focal) { var parts=(r.sets||[]).map(function(s,i){return setLabel(r,s,i,focal||"me");});if(r.iWon==null&&r.endTime==null&&parts.length&&!(r.sets[parts.length-1]||{}).isTieBreak){var gp=gameScoreString(r.currentPointsMe||0,r.currentPointsOpponent||0,focal||"me");if(gp)parts.push("("+gp+")");}return parts.join("  ")||"Score unavailable"; }
  function gameScoreString(me,opp,focal){if(focal==="opponent"){var x=me;me=opp;opp=x;}if(!(me>0||opp>0))return null;if(me>=3&&opp>=3)return me===opp?"Deuce":me>opp?"AD–40":"40–AD";var labels=["0","15","30","40"];return (labels[me]||String(me))+"–"+(labels[opp]||String(opp));}
  function statsFor(points, focal) {
    return window.DeuceMateTracking.matchStatsSummary(points, focal);
  }
  function activitySplit(record) {
    var count = (record.sets || []).length, points = record.stats || [], elapsed = record.setElapsed || {}, indices = Array.from({ length: count }, function (_, i) { return i; });
    var durations = indices.map(function (i) { return Math.max(0, Number(elapsed[i] || 0)); }), totalDuration = durations.reduce(function (a, b) { return a + b; }, 0);
    var weights = totalDuration > 0 ? durations : indices.map(function (i) { return points.filter(function (p) { return p.setIndex === i; }).length; }), totalWeight = weights.reduce(function (a, b) { return a + b; }, 0);
    var samples = points.filter(function (p) { return p.stepsCumulative != null; }).sort(function (a, b) { return a.timestamp - b.timestamp; }), ends = {}, prior = 0;
    samples.forEach(function (p) { ends[p.setIndex] = p.stepsCumulative; });
    var deltas = indices.map(function (i) { var end = ends[i] == null ? prior : ends[i], delta = Math.max(0, end - prior); prior = Math.max(prior, end); return delta; }), totalDelta = deltas.reduce(function (a, b) { return a + b; }, 0);
    var useSamples = samples.length >= 2 && totalDelta > 0 && indices.every(function (i) { return !points.some(function (p) { return p.setIndex === i; }) || ends[i] != null; });
    var out = { steps: {}, calories: {} };
    indices.forEach(function (i) {
      if (record.steps > 0 && (useSamples || totalWeight > 0)) out.steps[i] = Math.round(record.steps * (useSamples ? deltas[i] / totalDelta : weights[i] / totalWeight));
      if (record.kcal > 0 && totalWeight > 0) out.calories[i] = record.kcal * weights[i] / totalWeight;
    }); return out;
  }
  function comparisonRows(points, focal) {
    var a = statsFor(points, focal), b = statsFor(points, other(focal));
    function ratio(n, d) { return d ? (n / d).toFixed(2) : n ? "∞" : "—"; }
    var rows = [
      ["Points won", a.pointsWon, b.pointsWon],
      ["1st serve in", percent(a.firstServeIn, a.firstServeTotal), percent(b.firstServeIn, b.firstServeTotal)],
      ["1st serve points won", percent(a.firstServeWins, a.firstServeIn), percent(b.firstServeWins, b.firstServeIn)],
      ["2nd serve in", percent(a.secondServeIn, a.secondServeTotal), percent(b.secondServeIn, b.secondServeTotal)],
      ["2nd serve points won", percent(a.secondServeWins, a.secondServeTotal), percent(b.secondServeWins, b.secondServeTotal)],
      ["Return points won (1st)", percent(a.returnWinsOnFirst, a.returnOppsOnFirst), percent(b.returnWinsOnFirst, b.returnOppsOnFirst)],
      ["Return points won (2nd)", percent(a.returnWinsOnSecond, a.returnOppsOnSecond), percent(b.returnWinsOnSecond, b.returnOppsOnSecond)],
      ["Winners", a.myWinners, b.myWinners], ["Unforced errors", a.myUnforcedErrors, b.myUnforcedErrors],
      ["Forced errors", a.myForcedErrors, b.myForcedErrors], ["Double faults", a.myDoubleFaults, b.myDoubleFaults],
      ["Winners / unforced errors", ratio(a.myWinners, a.myUnforcedErrors), ratio(b.myWinners, b.myUnforcedErrors)],
      ["Break points converted", a.breakPointWins + "/" + a.breakPointOpps, b.breakPointWins + "/" + b.breakPointOpps],
      ["Break points saved", (a.breakPointsFaced - a.breakPointsLost) + "/" + a.breakPointsFaced, (b.breakPointsFaced - b.breakPointsLost) + "/" + b.breakPointsFaced],
      ["Big points won", percent(a.bigPointWins, a.bigPointTotal), percent(b.bigPointWins, b.bigPointTotal)],
      ["Normal points won", percent(a.normalPointWins, a.normalPointTotal), percent(b.normalPointWins, b.normalPointTotal)]
    ];
    a.rallyDepth.forEach(function (r) { var opp = b.rallyDepth.find(function (x) { return x.shot === r.shot; }); rows.push(["Rally depth · " + labelShot(r.shot), percent(r.wins, r.total), opp ? percent(opp.wins, opp.total) : "—"]); });
    a.scoreStates.forEach(function (r) { var opp = b.scoreStates.find(function (x) { return x.label === r.label; }); rows.push([r.label, percent(r.wins, r.total), opp ? percent(opp.wins, opp.total) : "—"]); });
    return rows;
  }
  var detailStates = new Map();
  var OUTCOMES = ["doubleFault", "winner", "unforcedError", "forcedError"];
  var SERVING = ["firstServe", "secondServe", "doubleFault", "ace", "serveForcedError"];
  var SHOTS = ["serve", "return", "servePlusOne", "rally"];
  var SHOT_COLORS = { serve: "#30B0C7", return: "#5856D6", servePlusOne: "#00C7BE", rally: "#A2845E" };
  function servingMatch(p, focal, key) {
    if (p.server !== focal || p.outcome === "uncategorized") return false;
    if (key === "firstServe") return !p.isSecondServe && p.outcome !== "doubleFault";
    if (key === "secondServe") return !!p.isSecondServe && p.outcome !== "doubleFault";
    if (key === "doubleFault") return p.outcome === "doubleFault";
    if (key === "ace") return p.winner === focal && p.outcome === "winner" && p.endingShot === "serve";
    return p.winner === focal && p.outcome === "forcedError" && p.endingShot === "serve";
  }
  function outcomeMatch(p, focal, key) {
    if (key === "winner") return p.winner === focal && p.outcome === "winner";
    if (key === "unforcedError" || key === "forcedError" || key === "doubleFault") return p.winner !== focal && p.outcome === key;
    return false;
  }
  function gameScoreLabel(p) {
    var g = p.gameScoreAtStart;
    if (!g) return "";
    var sv = g.server || 0, ret = g.returner || 0;
    if (g.isTiebreak) { if (p.winner === p.server) sv++; else ret++; return "TB " + (p.server === "me" ? sv + "–" + ret : ret + "–" + sv); }
    if (p.winner === p.server) sv++; else ret++;
    function tennis(a,b) { if (a >= 3 && b >= 3) return a === b ? "Deuce" : a > b ? "Ad–40" : "40–Ad"; var l=["0","15","30","40"]; return (l[a] || String(a))+"–"+(l[b] || String(b)); }
    return p.server === "me" ? tennis(sv,ret) : tennis(ret,sv);
  }
  function gameScoreBeforeLabel(p){var g=p.gameScoreAtStart;if(!g)return "";if(g.isTiebreak)return "TB "+g.server+"–"+g.returner;function tennis(a,b){if(a>=3&&b>=3)return a===b?"Deuce":a>b?"AD–40":"40–AD";var l=["0","15","30","40"];return(l[a]||String(a))+"–"+(l[b]||String(b));}return tennis(g.server,g.returner);}
  function scoreTimeline(record,points,focal) {
    var engine=window.DeuceMateScoring;if(!engine||!points.length||!points[0].gameScoreAtStart)return null;
    if(record.pointsPlayed!=null&&Number(record.pointsPlayed)!==points.length)return null;
    var first=points[0],firstGame=first.gameScoreAtStart;
    if((first.setIndex||0)!==0||firstGame.server!==0||firstGame.returner!==0)return null;
    var state=engine.freshState(record.format||"standard",first.server||"me"),snap=[],isDoubles=record.matchType==="doubles";
    state.matchType=isDoubles?"doubles":"singles";
    if(isDoubles){state.doublesServiceOrder=["me","opponentS1","partner","opponentS2"];state.doublesServiceIndex=0;state.doublesServer=first.server==="me"?"me":"opponentS1";state.currentServer=first.server;}
    function scoreLine(s){return s.sets.map(function(set,i){return setLabel(record,set,i,focal||"me");}).join("  ");}
    function gameLine(s,p,after){var last=s.sets[s.sets.length-1];if(!last)return "";if(p.gameScoreAtStart&&p.gameScoreAtStart.isTiebreak){var sv=p.gameScoreAtStart.server||0,ret=p.gameScoreAtStart.returner||0;if(after){if(p.winner===p.server)sv++;else ret++;}var serverIsMe=(focal||"me")===p.server;return "TB "+(serverIsMe?sv:ret)+"–"+(serverIsMe?ret:sv);}return gameScoreString(s.currentPointsMe,s.currentPointsOpponent,focal||"me")||"";}
    for(var i=0;i<points.length;i++){
      var p=points[i],g=p.gameScoreAtStart;if(!g||Number(p.setIndex||0)!==state.sets.length-1)return null;
      if(isDoubles)state.currentServer=p.server;else if(state.currentServer!==p.server)return null;
      var last=state.sets[state.sets.length-1];if(!last)return null;
      var expectedServer=last.isTieBreak?(p.server==="me"?last.tieBreakPointsMe:last.tieBreakPointsOpponent):(p.server==="me"?state.currentPointsMe:state.currentPointsOpponent);
      var expectedReturner=last.isTieBreak?(p.server==="me"?last.tieBreakPointsOpponent:last.tieBreakPointsMe):(p.server==="me"?state.currentPointsOpponent:state.currentPointsMe);
      if(Number(g.server)!==expectedServer||Number(g.returner)!==expectedReturner||!!g.isTiebreak!==!!last.isTieBreak)return null;
      var before=scoreLine(state),gameBefore=gameLine(state,p,false);
      state=engine.pointWon(state,p.winner).state;
      var gameAfter=gameLine(state,p,true)||"0–0",after=scoreLine(state);snap.push({before:before+(gameBefore?" · "+gameBefore:""),after:after+" · "+gameAfter,matchAfter:after,gameBefore:gameBefore,gameAfter:gameAfter,gameAfterSnapshot:{server:state.currentPointsMe,returner:state.currentPointsOpponent,isTiebreak:!!state.sets[state.sets.length-1].isTieBreak}});
    }
    var sets=record.sets||[];if(sets.length!==state.sets.length)return null;
    for(var j=0;j<sets.length;j++){var a=sets[j],b=state.sets[j];if(!b||Number(a.gamesMe||0)!==Number(b.gamesMe||0)||Number(a.gamesOpponent||0)!==Number(b.gamesOpponent||0)||!!a.isTieBreak!==!!b.isTieBreak)return null;if(b.isTieBreak&&(Number(a.tieBreakPointsMe||0)!==Number(b.tieBreakPointsMe||0)||Number(a.tieBreakPointsOpponent||0)!==Number(b.tieBreakPointsOpponent||0)))return null;}
    if(!record.endTime&&(Number(record.currentPointsMe||0)!==Number(state.currentPointsMe||0)||Number(record.currentPointsOpponent||0)!==Number(state.currentPointsOpponent||0)))return null;
    return snap;
  }
  function orientScore(text,focal){if(!text||focal==="me")return text;return text.replace(/(TB\s*)?(\d+)–(\d+)/g,function(_,tb,a,b){return(tb||"")+b+"–"+a;});}
  function section(title, content) { var s = el("section", "pr-section"); s.appendChild(el("h3", "pr-section-title", title)); s.appendChild(content); return s; }
  function statRow(label, a, b, kind) {
    var row = el("div", "pr-stat-row"); row.appendChild(el("span", "pr-stat-name", label));
    row.appendChild(el("strong", "pr-stat-value", safe(a))); row.appendChild(el("strong", "pr-stat-value pr-opponent", safe(b)));
    if (kind) row.classList.add(kind); return row;
  }
  function metricCard(title, value, sub) { var d = el("div", "pr-metric"); d.appendChild(el("span", "pr-metric-label", title)); d.appendChild(el("strong", "pr-metric-value", value)); if (sub) d.appendChild(el("span", "pr-metric-sub", sub)); return d; }
  function escHTML(s) { return safe(s).replace(/[&<>"']/g, function (c) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]; }); }
  function fileBase(r) { return "deucemate-match-" + safe(r.id || "report").replace(/[^a-z0-9_-]/gi, "-"); }
  function exportContext() {return {score:score,setLabel:setLabel,scoreTimeline:scoreTimeline,pointSteps:pointSteps,graphSteps:graphSteps,activitySplit:activitySplit,outcomeMatch:outcomeMatch,servingMatch:servingMatch,graphSymbol:graphSymbol};}
  function exportSettings(level) {var settings=window.DeuceMatePhone?window.DeuceMatePhone.settings:{};return Object.assign({},settings,level?{playerNTRP:level}:{});}
  function reportText(r,pts,focal,kind,level) {return window.DeuceMatePhoneExport.text(r,pts,focal||"me",kind||"full",exportSettings(level),exportContext());}
  function pointSteps(points,index) { if(index<1||points[index].stepsCumulative==null||points[index-1].stepsCumulative==null)return null;return Math.max(0,points[index].stepsCumulative-points[index-1].stepsCumulative); }
  function graphSteps(points, totalSteps) {
    var samples = points.map(function (point, index) { return point.stepsCumulative == null ? null : { pointIndex: index, cumulative: Number(point.stepsCumulative) }; }).filter(Boolean), previous = 0;
    if (samples.length >= 2) {
      var base = samples[0].cumulative;
      return samples.map(function (sample) { var cumulative = Math.max(0, sample.cumulative - base), delta = Math.max(0, cumulative - previous); previous = cumulative; return { pointIndex: sample.pointIndex, cumulative: cumulative, perPoint: delta }; });
    }
    var total = Number(totalSteps || 0);
    return total > 0 && points.length ? points.map(function (_, index) { var cumulative = Math.floor((index + 1) / points.length * total), delta = Math.max(0, cumulative - previous); previous = cumulative; return { pointIndex: index, cumulative: cumulative, perPoint: delta }; }) : [];
  }
  function graphSelection(record, points, index, timeline) {
    var point = points[index]; if (!point) return null;
    var through = points.slice(0, index + 1), me = through.filter(function (p) { return p.winner === "me"; }).length;
    var snapshot = timeline && timeline[index], gameAfter = snapshot ? snapshot.gameAfter : null;
    // A suffix can still have a known game score. Reduce that one rally from
    // its saved snapshot without inventing the unknown games offset.
    var game = point.gameScoreAtStart, engine = window.DeuceMateScoring;
    if (!snapshot && game && engine && record.sets[point.setIndex]) {
      var serverIsMe = point.server === "me", rawMe = serverIsMe ? game.server : game.returner, rawOpp = serverIsMe ? game.returner : game.server;
      if (game.isTiebreak) gameAfter = "TB " + (rawMe + (point.winner === "me" ? 1 : 0)) + "–" + (rawOpp + (point.winner === "opponent" ? 1 : 0));
      else {
        var state = engine.freshState(record.format, point.server);
        state.sets = record.sets.slice(0, point.setIndex).concat([{ gamesMe: 0, gamesOpponent: 0, isTieBreak: false, tieBreakPointsMe: 0, tieBreakPointsOpponent: 0 }]);
        state.currentPointsMe = rawMe; state.currentPointsOpponent = rawOpp;
        var after = engine.pointWon(state, point.winner).state;
        gameAfter = gameScoreString(after.currentPointsMe, after.currentPointsOpponent, "me") || "0–0";
      }
    }
    var movement = graphSteps(points, record.steps).find(function (sample) { return sample.pointIndex === index; });
    return { set: Number(point.setIndex || 0) + 1, point: through.filter(function (p) { return p.setIndex === point.setIndex; }).length,
      me: me, opponent: index + 1 - me, gameAfter: gameAfter, matchAfter: snapshot ? snapshot.matchAfter : null, steps: movement ? movement.perPoint : null };
  }
  function reportCSV(r, pts, focal) {
    var rows = [["Point", "Set", "Server", "Winner", "Outcome", "Ending shot", "Second serve", "Break point", "Recorder HR BPM", "Steps during point"]];
    pts.forEach(function (p, i) { rows.push([i + 1, (p.setIndex || 0) + 1, p.server === focal ? "Me" : "Opponent", p.winner === focal ? "Me" : "Opponent", labelOutcome(p.outcome), labelShot(p.endingShot), p.isSecondServe ? "Yes" : "No", p.isBreakPoint ? "Yes" : "No", p.heartRateBPM == null ? "" : p.heartRateBPM, pointSteps(pts,i) == null ? "" : pointSteps(pts,i)]); });
    return rows.map(function (row) { return row.map(function (x) { return '"' + safe(x).replace(/"/g, '""') + '"'; }).join(","); }).join("\r\n");
  }
  function standaloneHTML(r,pts,focal) {return window.DeuceMatePhoneExport.html(r,pts,focal||"me",exportSettings(),exportContext());}
  function exportModel(r,pts,focal) {return window.DeuceMatePhoneExport.model(r,pts,focal||"me",exportSettings(),exportContext());}

  // Match the native BasicChartSymbolShape mapping so categories remain
  // distinguishable without relying on colour, including in offline reports.
  function graphSymbol(family, category, radius) {
    var symbols = {
      outcome: { winner: "circle", doubleFault: "square", unforcedError: "cross", forcedError: "triangle" },
      serving: { firstServe: "circle", secondServe: "asterisk", doubleFault: "square", ace: "pentagon", serveForcedError: "triangle" },
      shot: { serve: "pentagon", return: "asterisk", servePlusOne: "plus", rally: "triangle" }
    }, shape = (symbols[family] || {})[category] || "circle", r = radius;
    if (shape === "circle") return { shape: shape, tag: "circle", attrs: { cx: 0, cy: 0, r: r } };
    if (shape === "square") return { shape: shape, tag: "rect", attrs: { x: -r, y: -r, width: r * 2, height: r * 2 } };
    if (shape === "pentagon" || shape === "triangle") {
      var sides = shape === "pentagon" ? 5 : 3, points = [];
      for (var i = 0; i < sides; i++) { var angle = -Math.PI / 2 + i * Math.PI * 2 / sides; points.push(Math.cos(angle) * r + "," + Math.sin(angle) * r); }
      return { shape: shape, tag: "polygon", attrs: { points: points.join(" ") } };
    }
    var a = r * .35, d = "M " + -a + " " + -r + " H " + a + " V " + -a + " H " + r + " V " + a + " H " + a + " V " + r + " H " + -a + " V " + a + " H " + -r + " V " + -a + " H " + -a + " Z";
    if (shape === "asterisk") d = "M 0 " + -r + " L " + a + " " + -a + " L " + r + " " + -a + " L " + a + " 0 L " + r + " " + a + " L " + a + " " + a + " L 0 " + r + " L " + -a + " " + a + " L " + -r + " " + a + " L " + -a + " 0 L " + -r + " " + -a + " L " + -a + " " + -a + " Z";
    return { shape: shape, tag: "path", attrs: { d: d, transform: shape === "cross" ? "rotate(45)" : "" } };
  }
  function graphSvg(allPoints, state, select, viewRange, showXAxis, externalGestures) {
    var offset=viewRange?viewRange.start:0,points=viewRange?allPoints.slice(viewRange.start,viewRange.end):allPoints;
    var allTotals=allPoints.reduce(function(total,p){total[p.winner]++;return total;},{me:0,opponent:0});
    var ns="http://www.w3.org/2000/svg", w=340,h=250,left=29,right=w-(state.showHR||state.showSteps?38:10),top=15,bottom=224,max=Math.max(allTotals.me,allTotals.opponent,1),xCount=Math.max(points.length,1);
    function tickStep(span,count){var raw=Math.max(1,span/count),power=Math.pow(10,Math.floor(Math.log10(raw))),scaled=raw/power;return(scaled<Math.sqrt(2)?1:scaled<Math.sqrt(5)?2:scaled<Math.sqrt(12.5)?2.5:scaled<Math.sqrt(50)?5:10)*power;}
    var yStep=Math.max(1,tickStep(max,4));max=Math.ceil(max/yStep)*yStep;
    var svg=document.createElementNS(ns,"svg");svg.setAttribute("viewBox","0 0 "+w+" "+h);svg.classList.add("pr-chart-svg");
    function pointX(index){return left+(right-left)*index/xCount;}
    var setRanges=[];points.forEach(function(p,i){var set=Number(p.setIndex||0),tb=!!(p.gameScoreAtStart&&p.gameScoreAtStart.isTiebreak),key=set+":"+tb,current=setRanges[setRanges.length-1];if(!current||current.key!==key){if(current)current.end=pointX(i);setRanges.push({key:key,set:set,isTiebreak:tb,start:i===0?left:pointX(i),end:right,label:tb?"TB":"Set "+(set+1)});}});
    setRanges.forEach(function(b,i){var rect=document.createElementNS(ns,"rect"),fills={1:"#3478f6",2:"#f97316",3:"#a855f7"};rect.setAttribute("x",b.start);rect.setAttribute("y",top);rect.setAttribute("width",Math.max(0,b.end-b.start));rect.setAttribute("height",bottom-top);rect.setAttribute("fill",b.isTiebreak?"#eab308":(fills[b.set+1]||"#9298a0"));rect.setAttribute("opacity",b.isTiebreak?".22":".10");svg.appendChild(rect);var label=document.createElementNS(ns,"text");label.setAttribute("x",(b.start+b.end)/2);label.setAttribute("y",top+9);label.setAttribute("text-anchor","middle");label.setAttribute("font-size","10");label.setAttribute("fill","#829087");label.textContent=b.label;svg.appendChild(label);});
    function line(x1,y1,x2,y2,color,dash){var n=document.createElementNS(ns,"line");n.setAttribute("x1",x1);n.setAttribute("x2",x2);n.setAttribute("y1",y1);n.setAttribute("y2",y2);n.setAttribute("stroke",color);if(dash)n.setAttribute("stroke-dasharray",dash);svg.appendChild(n);}
    for(var value=0;value<=max;value+=yStep){var y=bottom-(bottom-top)*value/max;line(left,y,right,y,"#ffffff26");var label=document.createElementNS(ns,"text");label.setAttribute("x",2);label.setAttribute("y",y+3);label.setAttribute("font-size","11");label.setAttribute("fill","#829087");label.textContent=value;svg.appendChild(label);}
    if(showXAxis){var xStep=Math.max(1,tickStep(xCount,4)),firstTick=Math.ceil(offset/xStep)*xStep;for(var xt=firstTick;xt<=offset+xCount;xt+=xStep){var x=left+(right-left)*(xt-offset)/xCount,tickLine=document.createElementNS(ns,"line");tickLine.setAttribute("x1",x);tickLine.setAttribute("x2",x);tickLine.setAttribute("y1",bottom);tickLine.setAttribute("y2",bottom+3);tickLine.setAttribute("stroke","#829087");svg.appendChild(tickLine);var xLabel=document.createElementNS(ns,"text");xLabel.setAttribute("x",x);xLabel.setAttribute("y",bottom+16);xLabel.setAttribute("text-anchor",xt===offset?"start":"middle");xLabel.setAttribute("font-size","9");xLabel.setAttribute("fill","#829087");xLabel.textContent=String(xt);svg.appendChild(xLabel);}}
    function secondaryAxis(minimum, maximum, color, title) {
      var step=tickStep(maximum-minimum,3);
      for(var value=Math.ceil(minimum/step)*step;value<=maximum;value+=step){
        var fraction=(value-minimum)/Math.max(1,maximum-minimum),label = document.createElementNS(ns, "text");
        label.dataset.axis=title;label.setAttribute("x", right + 4); label.setAttribute("y", bottom - (bottom - top) * fraction + 3); label.setAttribute("fill", color); label.setAttribute("font-size", "9");
        label.textContent=title==="steps"&&value>=1000?String(Math.round(value/100)/10)+"k":String(Math.round(value));svg.append(label);
      }
    }
    var m=allPoints.slice(0,offset).filter(function(p){return p.winner==="me";}).length,o=offset-m,me=[left+","+(bottom-(bottom-top)*m/max)],opp=[left+","+(bottom-(bottom-top)*o/max)],coords=[];
    points.forEach(function(p,i){if(p.winner==="me")m++;else o++;var x=pointX(i+1), ym=bottom-(bottom-top)*m/max, yo=bottom-(bottom-top)*o/max;me.push(x+","+ym);opp.push(x+","+yo);coords.push({x:x,ym:ym,yo:yo,p:p,i:i});});
    function poly(coords,color,stepped){if(!coords.length)return null;var n=document.createElementNS(ns,stepped?"path":"polyline");n.setAttribute("fill","none");n.setAttribute("stroke",color);n.setAttribute("stroke-width","2.5");if(stepped){var d="M "+coords[0].split(",").join(" ");for(var i=1;i<coords.length;i++){var pair=coords[i].split(",");d+=" H "+pair[0]+" V "+pair[1];}n.setAttribute("d",d);}else n.setAttribute("points",coords.join(" "));svg.appendChild(n);return n;}
    poly(me,"var(--phone-me, #72d5a0)",true);poly(opp,"var(--phone-opp, #e08a85)",true);
    var selectedLocal=state.selected-offset;if(selectedLocal>=0&&selectedLocal<points.length){var selectedRule=document.createElementNS(ns,"line"),selectedX=coords[selectedLocal].x;selectedRule.setAttribute("x1",selectedX);selectedRule.setAttribute("x2",selectedX);selectedRule.setAttribute("y1",top);selectedRule.setAttribute("y2",bottom);selectedRule.setAttribute("stroke","#8d9690");selectedRule.setAttribute("stroke-dasharray","3 3");svg.appendChild(selectedRule);}
    coords.forEach(function(v){var p=v.p,marks=[];
      OUTCOMES.forEach(function(k){if(state.outcomesMe.indexOf(k)>=0&&outcomeMatch(p,"me",k))marks.push({family:"outcome",category:k,y:v.ym,color:({winner:"#FFCC00",forcedError:"#AF52DE",unforcedError:"#FF3B30",doubleFault:"#FF9500"})[k],label:"Me "+labelOutcome(k)});if(state.outcomesOpp.indexOf(k)>=0&&outcomeMatch(p,"opponent",k))marks.push({family:"outcome",category:k,y:v.yo,color:({winner:"#FFCC00",forcedError:"#AF52DE",unforcedError:"#FF3B30",doubleFault:"#FF9500"})[k],label:"Opp "+labelOutcome(k)});});
      SERVING.forEach(function(k){if(state.serveMe.indexOf(k)>=0&&servingMatch(p,"me",k))marks.push({family:"serving",category:k,y:v.ym,color:({firstServe:"#30B0C7",secondServe:"#5856D6",doubleFault:"#FF9500",ace:"#FFCC00",serveForcedError:"#AF52DE"})[k],label:"Me "+k});if(state.serveOpp.indexOf(k)>=0&&servingMatch(p,"opponent",k))marks.push({family:"serving",category:k,y:v.yo,color:({firstServe:"#30B0C7",secondServe:"#5856D6",doubleFault:"#FF9500",ace:"#FFCC00",serveForcedError:"#AF52DE"})[k],label:"Opp "+k});});
      if(p.endingShot&&p.winner==="me"&&state.shotsWon.indexOf(p.endingShot)>=0)marks.push({family:"shot",category:p.endingShot,y:v.ym,color:SHOT_COLORS[p.endingShot],label:"Won @ "+labelShot(p.endingShot)});
      if(p.endingShot&&p.winner==="opponent"&&state.shotsLost.indexOf(p.endingShot)>=0)marks.push({family:"shot",category:p.endingShot,y:v.yo,color:SHOT_COLORS[p.endingShot],label:"Lost @ "+labelShot(p.endingShot)});
      marks.forEach(function(mark){
        var symbol=graphSymbol(mark.family,mark.category,state.selected===v.i+offset?5.5:4.2),c=document.createElementNS(ns,symbol.tag);
        Object.keys(symbol.attrs).forEach(function(key){c.setAttribute(key,symbol.attrs[key]);});
        c.classList.add("pr-chart-mark");c.dataset.symbol=symbol.shape;c.setAttribute("transform","translate("+v.x+" "+mark.y+") "+(symbol.attrs.transform||""));c.setAttribute("fill",mark.color);c.setAttribute("stroke","white");c.setAttribute("stroke-width",".65");c.setAttribute("tabindex","0");c.setAttribute("role","button");c.setAttribute("aria-label","Point "+(v.i+offset+1)+" "+mark.label);c.onclick=function(){if(!externalGestures)select(v.i+offset);};c.onkeydown=function(e){if(e.key==="Enter"||e.key===" "){e.preventDefault();select(v.i+offset);}};svg.appendChild(c);
      });
      var hit=document.createElementNS(ns,"circle");hit.classList.add("pr-chart-hit");if(state.selected===v.i+offset)hit.classList.add("is-selected");hit.setAttribute("cx",v.x);hit.setAttribute("cy",v.ym);hit.setAttribute("r",state.selected===v.i+offset?8:6);hit.setAttribute("fill","transparent");hit.setAttribute("stroke",state.selected===v.i+offset?"#a6ada8":"transparent");hit.setAttribute("tabindex","0");hit.setAttribute("role","button");hit.setAttribute("aria-label","Inspect point "+(v.i+offset+1));hit.onclick=function(){if(!externalGestures)select(v.i+offset);};hit.onkeydown=function(e){if(e.key==="Enter"||e.key===" "){e.preventDefault();select(v.i+offset);}};svg.appendChild(hit);
    });
    if(state.showHR){var hr=allPoints.map(function(p,i){return p.heartRateBPM==null?null:{pointIndex:i,bpm:Number(p.heartRateBPM)};}).filter(Boolean),mode=state.hrMode||"snapshot",rawValues=hr.map(function(x){return x.bpm;}),rawMin=rawValues.length?Math.max(40,Math.min.apply(null,rawValues)-10):50,rawMax=rawValues.length?Math.max(Math.max.apply(null,rawValues)+10,rawMin+20):200;if(hr.length)secondaryAxis(rawMin,rawMax,"#ff3b30b3","bpm");if(mode!=="snapshot"&&hr.length>=2){var radius=mode==="smoothed"?2:1;hr=hr.map(function(entry,i){var values=hr.slice(Math.max(0,i-radius),Math.min(hr.length,i+radius+1)),avg=values.reduce(function(sum,x){return sum+x.bpm;},0)/values.length;return{pointIndex:entry.pointIndex,bpm:Math.round(avg)};});}var visibleHR=hr.filter(function(x){return x.pointIndex>=offset&&x.pointIndex<offset+points.length;});if(visibleHR.length)poly(visibleHR.map(function(x){var local=x.pointIndex-offset;return pointX(local+1)+","+(bottom-(bottom-top)*(x.bpm-rawMin)/Math.max(1,rawMax-rawMin));}),"#ff3b30b3");}
    if(state.showSteps){var steps=graphSteps(allPoints,state.totalSteps),field=state.stepsMode==="perPoint"?"perPoint":"cumulative",visibleSteps=steps.filter(function(x){return x.pointIndex>=offset&&x.pointIndex<offset+points.length;}),stepMax=Math.max.apply(null,steps.map(function(x){return x[field];}).concat([1]));if(visibleSteps.length){secondaryAxis(0,stepMax,"#34c759bf","steps");var previous=steps.filter(function(x){return x.pointIndex<offset;}).slice(-1)[0],base=previous?previous[field]:0,stepCoords=[left+","+(bottom-(bottom-top)*base/stepMax)].concat(visibleSteps.map(function(x){return pointX(x.pointIndex-offset+1)+","+(bottom-(bottom-top)*x[field]/stepMax);})),stepLine=poly(stepCoords,"#34c759bf");if(stepLine)stepLine.setAttribute("stroke-dasharray","5 3");}}
    svg.style.touchAction = "none";
    svg.addEventListener("pointerdown", function (event) {
      if (!points.length || externalGestures) return;
      event.preventDefault();
      var bounds = svg.getBoundingClientRect(), lastIndex = -1;
      function move(e) {
        var x = (e.clientX - bounds.left) / Math.max(1, bounds.width) * w;
        var index = Math.max(0, Math.min(points.length - 1, Math.round((x - left) / (right - left) * xCount) - 1));
        if (index !== lastIndex) { lastIndex = index; select(index+offset); }
      }
      function end() { document.removeEventListener("pointermove", move); document.removeEventListener("pointerup", end); document.removeEventListener("pointercancel", end); }
      document.addEventListener("pointermove", move); document.addEventListener("pointerup", end); document.addEventListener("pointercancel", end);
      move(event);
    });
    return svg;
  }

  // Mirror HealthExportConsent.presentFields: an opponent summary excludes
  // per-point health; HTML and full reports include the raw point table.
  function exportFields(record,focal,includesRawPoints) {
    var heart=(record.stats||[]).some(function(p){return p.heartRateBPM!=null;}),perSteps=(record.stats||[]).some(function(p){return p.stepsCumulative!=null;});
    var fields=[];
    if(focal==="me"){if(heart)fields.push("heart rate","heart-rate zones");if((record.steps||0)>0||perSteps)fields.push("steps");}
    else {if(heart&&includesRawPoints)fields.push("heart rate");if((record.steps||0)>0||(perSteps&&includesRawPoints))fields.push("steps");}
    if((record.kcal||0)>0)fields.push("calories");if((record.distance||0)>0)fields.push("distance");return fields;
  }
  function healthDisclosure(phone,fields,confirmLabel,action) {
    var list=fields.length<3?fields.join(" and "):fields.slice(0,-1).join(", ")+", and "+fields[fields.length-1];
    var body=el("div","pr-consent"),actions=el("div","pr-consent-actions");
    body.append(el("p","","This export includes your recorded "+list+". DeuceMate has no server and never receives it, but whoever or whatever you send it to — a person, the Files app or iCloud Drive, or an AI service will receive it."));
    actions.append(phone.button("Cancel",function(){phone.closeSheet();}),phone.button(confirmLabel,action));body.append(actions);
    phone.showSheet("Share health data?",body,{presentation:"alert",variant:"health",width:320});
  }
  function performExport(phone,record,focal,format) {
    var fields=exportFields(record,focal,format!=="summary"),base=fileBase(record)+(focal==="opponent"?"-opponent":"");
    function go(){
      var pts=record.stats||[],saved;
      if(format==="preview"){
        var frame=document.createElement("iframe");frame.title="Interactive match report preview";frame.setAttribute("sandbox","allow-scripts");frame.className="pr-report-preview";frame.srcdoc=standaloneHTML(record,pts,focal);phone.showSheet("Interactive report preview",frame,{presentation:"cover"});return;
      }
      if (phone.closeSheet) phone.closeSheet();
      if(format==="txt"||format==="summary"||format==="ai")saved=phone.download(base+(format==="txt"?"_full":"_"+format)+".txt","text/plain;charset=utf-8",reportText(record,pts,focal,format==="txt"?"full":format,phone.settings.playerNTRP));
      else if(format==="csv")saved=phone.download(base+".csv","text/csv;charset=utf-8",reportCSV(record,pts,focal));
      else saved=phone.download(base+".html","text/html;charset=utf-8",standaloneHTML(record,pts,focal));
      if(saved)phone.notify("Report downloaded");
    }
    if(!fields.length){go();return;}
    healthDisclosure(phone,fields,"Share",go);
  }
  function openShareMenu(phone,record) {
    var menu=el("div","pr-share-menu"),main=el("div","pr-share-sections"),submenu=null;
    function row(label,icon,action,arrow) {
      var b=phone.button("",action,"pr-share-row");
      if(icon)b.append(phone.icon(icon));
      b.append(el("span","",label));if(arrow)b.append(phone.icon("chevron"));return b;
    }
    function closeSubmenu() {
      if(!submenu)return;submenu.remove();submenu=null;main.inert=false;main.removeAttribute("aria-hidden");menu.classList.remove("pr-submenu-open");interactive.setAttribute("aria-expanded","false");interactive.focus();
    }
    var interactive=row("Interactive Web Page","safari",function(){
      if(submenu){closeSubmenu();return;}
      submenu=el("div","pr-share-submenu");submenu.setAttribute("aria-label","Interactive Web Page");
      var heading=row("Interactive Web Page","safari",closeSubmenu,true);heading.classList.add("pr-share-submenu-heading");heading.setAttribute("aria-expanded","true");
      submenu.append(heading,row("My Perspective",null,function(){performExport(phone,record,"me","html");}),row("Opponent's Perspective",null,function(){performExport(phone,record,"opponent","html");}));
      main.inert=true;main.setAttribute("aria-hidden","true");menu.classList.add("pr-submenu-open");interactive.setAttribute("aria-expanded","true");menu.append(submenu);heading.focus();
    },true);
    interactive.setAttribute("aria-haspopup","true");interactive.setAttribute("aria-expanded","false");
    var web=el("div","pr-share-group");web.append(el("div","pr-share-group-title","Interactive"),interactive);main.append(web);
    [["My Stats","me"],["Opponent's Stats","opponent"]].forEach(function(side){
      var group=el("div","pr-share-group");group.setAttribute("role","group");group.setAttribute("aria-label",side[0]);
      group.append(el("div","pr-share-group-title",side[0]),row("Share Summary","summary",function(){performExport(phone,record,side[1],"summary");}));
      if((record.stats||[]).length)group.append(row("Share Summary + Raw Points","table",function(){performExport(phone,record,side[1],"txt");}));
      main.append(group);
    });menu.append(main);
    menu.addEventListener("keydown",function(event){
      if((event.key==="Escape"||event.key==="ArrowLeft")&&submenu){event.preventDefault();event.stopPropagation();closeSubmenu();}
      else if(event.key==="ArrowRight"&&event.target===interactive){event.preventDefault();interactive.click();}
    });
    phone.showSheet("Share match",menu,{presentation:"menu",variant:"share",width:250,anchor:function(){return document.querySelector('#iphone-demo .phone-nav [aria-label="Share match"]').getBoundingClientRect();}});
  }
  function openBrowserExports(phone,record) {
    var tools=el("div","pr-browser-exports");tools.append(phone.note("Extra browser tools. The app’s Share menu offers interactive web pages and text summaries."));addExportMenu(phone,record,tools);phone.showSheet("Browser export tools",tools);
  }
  function addExportMenu(phone, record, host) {
    var sectionEl = el("section", "pr-section"), actions = el("div", "pr-export-actions"); sectionEl.append(el("h3", "pr-section-title", "Export match"));
    [["My Stats", "me"], ["Opponent’s Stats", "opponent"]].forEach(function (side) {
      var group = el("div", "pr-export-group"); group.append(el("strong", "", side[0]));
      [["Interactive HTML", "html", "share"], ["Summary Text", "summary", "copy"], ["Full Match Text", "txt", "score"], ["AI Coaching Prompt", "ai", "sparkles"], ["CSV points", "csv", "stats"], ["Preview report", "preview", "expand"]].forEach(function (choice) {
        var b = phone.button("", function () { performExport(phone, record, side[1], choice[1]); }, "pr-export-button"); b.append(phone.icon(choice[2]), el("span", "", choice[0])); group.append(b);
      }); actions.append(group);
    }); sectionEl.append(actions); host.append(sectionEl);
  }

  function detail(phone, record) {
    var root = el("div", "phone-report"), pts = (record.stats || []).slice(), timeline=scoreTimeline(record,pts,"me"), scroll = el("div", "pr-scroll"); root.appendChild(scroll);
    var top = phone.card(); top.classList.add("pr-hero"); top.appendChild(el("div", "pr-overline", fmtDate(record.startTime) + " · " + fmtFormat(record)));
    // Retain the report's semantic heading without adding a non-native title row.
    top.appendChild(el("h2", "pr-title phone-visually-hidden", detailTitle(record)));
    var scoreRow = el("div", "pr-score-row"); scoreRow.appendChild(el("div", "pr-score", score(record,"me")));
    if (record.endTime) scoreRow.appendChild(el("span", "phone-result-badge " + (record.iWon === true ? "won" : record.iWon === false ? "lost" : "draw"), matchResult(record,"me")));
    top.appendChild(scoreRow);
    if (!record.endTime) {
      top.appendChild(el("div", "pr-meta", "ⓘ　 In Progress"));
      var endButton=phone.button("End at Current Score", function () { phone.endRecord(record); }, "phone-danger pr-end-match");endButton.setAttribute("aria-label","End at Current Score");top.appendChild(endButton);
    }
    var pwSlot=el("div","pr-pw-slot");top.appendChild(pwSlot);scroll.appendChild(top);
    var graphSection = el("section", "pr-section pr-native-graph"); graphSection.appendChild(el("h3", "pr-section-title", "Points Graph")); scroll.appendChild(graphSection);
    var tabbar = el("div", "pr-tabs"), statsTab = phone.button("Stats", null, "pr-tab active"), pointsTab = phone.button("Points", null, "pr-tab"); tabbar.appendChild(statsTab); tabbar.appendChild(pointsTab); if (pts.length) scroll.appendChild(tabbar);
    var content = el("div", "pr-content"); scroll.appendChild(content);
    var state = detailStates.get(record.id) || { tab: "stats", set: "all", selected: -1, showHR: false, showSteps: false, hrMode: "snapshot", stepsMode: "cumulative", outcomesMe: [], outcomesOpp: [], serveMe: [], serveOpp: [], shotsWon: [], shotsLost: [] };
    if(!state.hrMode)state.hrMode="snapshot";if(!state.stepsMode)state.stepsMode="cumulative";state.totalSteps=Number(record.steps||0);
    detailStates.set(record.id, state);
    statsTab.classList.toggle("active", state.tab === "stats"); pointsTab.classList.toggle("active", state.tab === "points");
    function filtered() { return pts.filter(function (p) { return state.set === "all" || Number(p.setIndex || 0) === Number(state.set); }); }
    function drawPointsWon(){pwSlot.replaceChildren();if(state.tab!=="stats")return;var scoped=filtered(),a=statsFor(scoped,"me"),b=statsFor(scoped,"opponent"),total=a.pointsWon+b.pointsWon;if(!total)return;var pw=el("div","pr-pw-card"),head=el("div","pr-pw-head");head.appendChild(el("div","pr-pw-side pr-pw-me","Me\n"+a.pointsWon+" pts · "+Math.round(a.pointsWon*100/total)+"%"));head.appendChild(el("div","pr-pw-mid","Points Won\n"+total+" total"));head.appendChild(el("div","pr-pw-side pr-pw-opp","Opp\n"+b.pointsWon+" pts · "+Math.round(b.pointsWon*100/total)+"%"));var bar=el("div","pr-pw-bar"),meBar=el("span"),oppBar=el("span");meBar.style.width=(a.pointsWon/total*100)+"%";oppBar.style.width=(b.pointsWon/total*100)+"%";bar.append(meBar,oppBar);pw.append(head,bar);pwSlot.appendChild(pw);}
    function setName(index) { return index === 2 && record.format === "standard" ? "TB" : "Set " + (index + 1); }
    function setFilter(parent) {
      var choices = [["all", "All"]].concat((record.sets || []).map(function (_, i) { return [String(i), setName(i)]; }));
      var picker = phone.segment("Set", state.set, choices, function (value) { state.set = value; state.selected = -1; paint(); drawGraph(); });
      var row = el("div", "pr-set-picker"); row.append(picker); parent.append(row);
    }
    function toggle(arr, value, fn) { var i = arr.indexOf(value); if (i < 0) arr.push(value); else arr.splice(i, 1); fn(); }
    function counts() { var m = statsFor(pts, "me"), o = statsFor(pts, "opponent"); return [m,o]; }
    function pillGroup(title, focal, keys, selected, match, names, colorFn, onChange) {
      var row = el("div", "pr-pill-row"); row.appendChild(el("span", "pr-pill-side", focal === "me" ? "Me" : focal === "won" ? "Won" : focal === "lost" ? "Lost" : "Opp"));
      keys.forEach(function (key) { var n = pts.filter(function (p) { return match(p, focal, key); }).length; var b = phone.button((names[key] || key) + " " + n, function () { toggle(selected, key, onChange); }, "pr-chip" + (selected.indexOf(key) >= 0 ? " selected" : "")); b.style.setProperty("--chip-color", colorFn(key)); b.setAttribute("aria-pressed", String(selected.indexOf(key) >= 0)); row.appendChild(b); });
      return row;
    }
    function appendInspector(parent) {
      if(state.selected<0||!pts[state.selected])return;
      var p=pts[state.selected],selection=graphSelection(record,pts,state.selected,timeline),info=el("div","pr-inspector"),head=el("div","pr-inspector-totals");
      head.append(el("strong","","Set "+selection.set+" · Pt "+selection.point),el("span","pr-me","● Me "+selection.me),el("span","pr-opp","● Opp "+selection.opponent));info.append(head);
      var chips=el("div","pr-inspector-scatter");
      function chip(text,color){var badge=el("span","pr-inspector-badge",text);badge.style.setProperty("--chip-color",color);chips.append(badge);}
      ["me","opponent"].forEach(function(focal){
        var mine=focal==="me",prefix=mine?"My ":"Opp ";
        (mine?state.outcomesMe:state.outcomesOpp).forEach(function(k){if(outcomeMatch(p,focal,k))chip(prefix+({winner:"W",forcedError:"FE",unforcedError:"UE",doubleFault:"DF"})[k],({winner:"#FFCC00",forcedError:"#AF52DE",unforcedError:"#FF3B30",doubleFault:"#FF9500"})[k]);});
        (mine?state.serveMe:state.serveOpp).forEach(function(k){if(servingMatch(p,focal,k))chip(prefix+({firstServe:"1st Serve",secondServe:"2nd Serve",doubleFault:"DF",ace:"Ace",serveForcedError:"Serve FE"})[k],({firstServe:"#30B0C7",secondServe:"#5856D6",doubleFault:"#FF9500",ace:"#FFCC00",serveForcedError:"#AF52DE"})[k]);});
      });
      if(p.endingShot&&(p.winner==="me"?state.shotsWon:state.shotsLost).indexOf(p.endingShot)>=0)chip((p.winner==="me"?"Won @ ":"Lost @ ")+({serve:"Serve",return:"Return",servePlusOne:"S+1",rally:"Rally"})[p.endingShot],SHOT_COLORS[p.endingShot]);
      if(chips.childElementCount)head.append(chips);
      var context=[p.server==="me"?"🎾 Serving":"Receiving"];
      if(selection.gameAfter)context.push("After point: "+selection.gameAfter);
      if(selection.matchAfter)context.push(selection.matchAfter);
      if(selection.steps!=null)context.push(selection.steps+" steps");
      info.appendChild(el("span","",context.join(" · ")));
      parent.appendChild(info);
    }
    function graphControls(onChange) {
      var controls=el("div","pr-graph-controls");
      if(pts.some(function(p){return p.outcome!=="uncategorized";})){
        controls.appendChild(el("h4","pr-graph-control-title","Outcomes"));
        var presets = el("div", "pr-quick-selects");
        function same(a, b) { return a.length === b.length && a.every(function (x) { return b.indexOf(x) >= 0; }); }
        [["won", "Points Won", ["winner"], ["unforcedError", "forcedError", "doubleFault"]], ["lost", "Points Lost", ["unforcedError", "forcedError", "doubleFault"], ["winner"]]].forEach(function (preset) {
          var active = same(state.outcomesMe, preset[2]) && same(state.outcomesOpp, preset[3]), count = pts.filter(function (p) { return p.outcome !== "uncategorized" && p.winner === (preset[0] === "won" ? "me" : "opponent"); }).length;
          var b = phone.button(preset[1] + " " + count, function () { state.outcomesMe = active ? [] : preset[2].slice(); state.outcomesOpp = active ? [] : preset[3].slice(); onChange(); }, "pr-quick-chip " + preset[0]); b.setAttribute("aria-pressed", String(active)); presets.append(b);
        }); controls.append(presets);

        var outcomeNames={winner:"W",forcedError:"FE",unforcedError:"UE",doubleFault:"DF"},outcomeColors=function(k){return({winner:"#FFCC00",forcedError:"#AF52DE",unforcedError:"#FF3B30",doubleFault:"#FF9500"})[k];};
        controls.appendChild(pillGroup("Outcomes","me",OUTCOMES,state.outcomesMe,outcomeMatch,outcomeNames,outcomeColors,onChange));controls.appendChild(pillGroup("Outcomes","opponent",OUTCOMES,state.outcomesOpp,outcomeMatch,outcomeNames,outcomeColors,onChange));
        controls.appendChild(el("h4","pr-graph-control-title","Serving"));
        var serveNames={firstServe:"1st Serve",secondServe:"2nd Serve",doubleFault:"DF",ace:"Ace",serveForcedError:"Serve FE"},serveColors=function(k){return({firstServe:"#30B0C7",secondServe:"#5856D6",doubleFault:"#FF9500",ace:"#FFCC00",serveForcedError:"#AF52DE"})[k];};
        controls.appendChild(pillGroup("Serving","me",SERVING,state.serveMe,servingMatch,serveNames,serveColors,onChange));controls.appendChild(pillGroup("Serving","opponent",SERVING,state.serveOpp,servingMatch,serveNames,serveColors,onChange));
      }
      var phases = SHOTS.filter(function (k) { return pts.some(function (p) { return p.endingShot === k; }); });
      if (phases.length) {
        controls.appendChild(el("h4", "pr-graph-control-title", "Ending Shots"));
        var quick = el("div", "pr-quick-selects");
        [["won", "All Won", state.shotsWon], ["lost", "All Lost", state.shotsLost]].forEach(function (side) {
          var active = phases.every(function (p) { return side[2].indexOf(p) >= 0; }) && (side[0] === "won" ? state.shotsLost : state.shotsWon).length === 0;
          var count = pts.filter(function (p) { return p.endingShot && p.winner === (side[0] === "won" ? "me" : "opponent"); }).length;
          var b = phone.button(side[1] + " " + count, function () { state.shotsWon = !active && side[0] === "won" ? phases.slice() : []; state.shotsLost = !active && side[0] === "lost" ? phases.slice() : []; onChange(); }, "pr-quick-chip " + side[0]); b.setAttribute("aria-pressed", String(active)); quick.append(b);
        }); controls.append(quick);
        function matchesShot(p, side, shot) { return p.endingShot === shot && p.winner === (side === "won" ? "me" : "opponent"); }
        var names = { serve: "Serve", return: "Return", servePlusOne: "S+1", rally: "Rally" };
        controls.append(pillGroup("Ending Shots", "won", phases, state.shotsWon, matchesShot, names, function (key) { return SHOT_COLORS[key]; }, onChange), pillGroup("Ending Shots", "lost", phases, state.shotsLost, matchesShot, names, function (key) { return SHOT_COLORS[key]; }, onChange));
      }
      var overlays = el("div", "pr-overlay-controls");
      [["showSteps", "Steps", pts.filter(function (p) { return p.stepsCumulative != null; }).length >= 2 || Number(state.totalSteps || 0) > 0], ["showHR", "Heart Rate", pts.some(function (p) { return p.heartRateBPM != null; })]].forEach(function (option) {
        if (!option[2]) return;
        var group = el("div", "pr-overlay-mode-group"), label = el("label", "pr-overlay-toggle"), box = el("input"); group.dataset.overlay = option[0];
        box.type = "checkbox"; box.checked = state[option[0]]; box.onchange = function () { state[option[0]] = box.checked; onChange(); }; label.append(box, document.createTextNode(option[1])); group.append(label);
        if (state[option[0]]) {
          var hr = option[0] === "showHR", modes = hr ? [["snapshot", "Raw"], ["averaged", "Per-point avg"], ["smoothed", "Smoothed"]] : [["cumulative", "Cumulative"], ["perPoint", "Per point"]], selectedMode = hr ? state.hrMode || "snapshot" : state.stepsMode || "cumulative";
          var picker = phone.segment(hr ? "Heart-rate mode" : "Steps mode", selectedMode, modes, function (value) { if (hr) state.hrMode = value; else state.stepsMode = value; onChange(); }); picker.classList.add("pr-overlay-mode-pills"); group.append(picker);
          if (hr && selectedMode === "averaged") group.append(el("small", "pr-mode-note", "Per-point averages are simulated from recorded samples; this demo does not fetch Health data."));
        }
        overlays.append(group);
      }); if (overlays.childNodes.length) controls.append(overlays);
      return controls;
    }
    function drawGraph() {
      graphSection.replaceChildren(); graphSection.appendChild(el("h3", "pr-section-title", "Points Graph"));
      if (!pts.length) {
        var empty=el("div","pr-chart-wrap pr-empty-graph");
        empty.append(phone.icon("chart"),el("strong","","No Points to Graph"));graphSection.append(empty);return;
      }
      var expand=phone.button("",openExpandedGraph,"pr-graph-expand");expand.setAttribute("aria-label","Expand graph");expand.appendChild(phone.icon("expand"));graphSection.appendChild(expand);
      var totals=counts()[0],clean={selected:state.selected,outcomesMe:[],outcomesOpp:[],serveMe:[],serveOpp:[],shotsWon:[],shotsLost:[],showHR:false,showSteps:false};
      var svg=graphSvg(pts,clean,function(idx){state.selected=idx;drawGraph();}),holder=el("div","pr-chart-wrap");holder.appendChild(svg);var leg=el("div","pr-chart-legend");leg.appendChild(el("span","pr-legend-me","Me"));leg.appendChild(el("span","pr-legend-opp","Opponent"));holder.appendChild(leg);graphSection.appendChild(holder);
      appendInspector(graphSection);graphSection.appendChild(el("p","pr-muted pr-graph-caption","⤢ Expand to filter points"+(record.steps>0||pts.some(function(p){return p.heartRateBPM!=null||p.stepsCumulative!=null;})?" & add overlays":"")));
    }
    function openExpandedGraph() {
      var panel = el("div", "pr-expanded-graph"), n = pts.length, minimum = Math.min(5, n), pointers = new Map(), gesture = null, lastTap = null;
      state.zoomLength = n; state.panStart = 0;
      var summarySlot = el("div", "pr-expanded-selection"), stage = el("div", "pr-expanded-stage"), controls = el("div", "pr-expanded-controls");
      panel.append(summarySlot, stage, controls);
      var reset = phone.button("", resetZoom, "pr-reset-zoom"); reset.append(phone.icon("expand")); reset.setAttribute("aria-label", "Reset Zoom");
      function resetZoom() { state.zoomLength = n; state.panStart = 0; update(); }
      function setRange(length, start) {
        state.zoomLength = Math.max(minimum, Math.min(n, Math.round(length)));
        state.panStart = Math.max(0, Math.min(n - state.zoomLength, Math.round(start)));
      }
      function drawStage() {
        stage.replaceChildren();
        var range = { start: state.panStart, end: Math.min(n, state.panStart + state.zoomLength) };
        var svg = graphSvg(pts, state, function (index) { state.selected = index; drawGraph(); update(); }, range, true, true);
        svg.setAttribute("preserveAspectRatio", "none");
        svg.tabIndex = 0; svg.setAttribute("aria-label", "Points graph. Drag across it to zoom, or pinch. Use plus or minus to zoom and arrow keys to pan.");
        svg.onkeydown = function (event) {
          if (["+", "=", "-", "ArrowLeft", "ArrowRight", "0"].indexOf(event.key) < 0) return;
          event.preventDefault(); event.stopPropagation();
          if (event.key === "0") resetZoom();
          else if (event.key === "ArrowLeft" || event.key === "ArrowRight") { setRange(state.zoomLength, state.panStart + (event.key === "ArrowRight" ? 1 : -1) * Math.max(1, Math.round(state.zoomLength / 5))); update(); }
          else { var next = Math.round(state.zoomLength * (event.key === "-" ? 1.4 : .7)), center = state.panStart + state.zoomLength / 2; setRange(next, center - next / 2); update(); }
          stage.querySelector("svg").focus({ preventScroll: true });
        };
        stage.append(svg); reset.disabled = state.zoomLength >= n && state.panStart === 0;
        panel.dataset.visiblePoints = state.zoomLength; panel.dataset.panStart = state.panStart;
      }
      function drawSummary() {
        summarySlot.replaceChildren(); appendInspector(summarySlot);
      }
      function drawControls() {
        var scroll = controls.scrollTop; controls.replaceChildren();
        var legend = el("div", "pr-chart-legend"); legend.append(el("span", "pr-legend-me", "Me"), el("span", "pr-legend-opp", "Opponent"));
        if(state.showHR)legend.append(el("span","pr-legend-hr","Heart Rate"));if(state.showSteps)legend.append(el("span","pr-legend-steps","Steps"));
        var coarse = window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
        controls.append(legend, graphControls(update), el("p", "pr-muted pr-graph-caption", coarse ? "Pinch to zoom · Drag to pan · Double-tap to reset" : "Drag across the chart to zoom · Shift-drag to pan · Double-click to reset"));
        controls.scrollTop = scroll;
      }
      function update() { drawStage(); drawSummary(); drawControls(); }
      function selectAt(event) {
        var box = stage.getBoundingClientRect(), plotRight = 340 - (state.showHR || state.showSteps ? 38 : 10), fraction = Math.max(0, Math.min(1, ((event.clientX - box.left) / box.width - 29 / 340) / ((plotRight - 29) / 340)));
        state.selected = Math.max(0, Math.min(n - 1, state.panStart + Math.round(fraction * state.zoomLength) - 1));
        drawGraph(); drawStage(); drawSummary();
      }
      function fractionAt(clientX) {
        var box = stage.getBoundingClientRect(), plotRight = 340 - (state.showHR || state.showSteps ? 38 : 10);
        return Math.max(0, Math.min(1, ((clientX - box.left) / box.width - 29 / 340) / ((plotRight - 29) / 340)));
      }
      var brushEl = null, zoomedByBrush = false;
      function drawBrush(x0, x1) {
        var box = stage.getBoundingClientRect();
        if (!brushEl) { brushEl = el("div", "pr-brush"); brushEl.setAttribute("aria-hidden", "true"); stage.append(brushEl); }
        brushEl.style.left = Math.min(x0, x1) - box.left + "px"; brushEl.style.width = Math.abs(x1 - x0) + "px";
      }
      function clearBrush() { if (brushEl) { brushEl.remove(); brushEl = null; } }
      function distance() { var a = Array.from(pointers.values()); return Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y); }
      stage.onpointerdown = function (event) {
        if (event.button !== 0) return;
        event.preventDefault(); stage.setPointerCapture(event.pointerId); pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
        if (pointers.size === 1) gesture = { x: event.clientX, y: event.clientY, start: state.panStart, length: state.zoomLength, moved: false, pinched: false };
        else if (pointers.size === 2) gesture = { distance: Math.max(1, distance()), center: state.panStart + state.zoomLength / 2, length: state.zoomLength, pinched: true };
      };
      stage.onpointermove = function (event) {
        if (!pointers.has(event.pointerId) || !gesture) return;
        event.preventDefault(); pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
        if (pointers.size >= 2 && gesture.pinched) { var length = gesture.length * gesture.distance / Math.max(1, distance()); setRange(length, gesture.center - Math.max(minimum, Math.min(n, Math.round(length))) / 2); drawStage(); }
        else if (!gesture.pinched) {
          var dx = event.clientX - gesture.x; if (Math.hypot(dx, event.clientY - gesture.y) > 6) gesture.moved = true;
          if (event.pointerType === "mouse" && !event.shiftKey && gesture.moved) { gesture.brush = event.clientX; drawBrush(gesture.x, event.clientX); }
          else if (state.zoomLength < n && gesture.moved) { setRange(gesture.length, gesture.start - dx / Math.max(1, stage.clientWidth * .885) * gesture.length); drawStage(); }
          else if (gesture.moved) selectAt(event);
        }
      };
      function finish(event) {
        if (!pointers.has(event.pointerId)) return;
        pointers.delete(event.pointerId);
        if (!pointers.size) {
          clearBrush();
          if (event.type === "pointerup" && gesture && gesture.brush != null && Math.abs(gesture.brush - gesture.x) > 8) {
            var f0 = fractionAt(Math.min(gesture.x, gesture.brush)), f1 = fractionAt(Math.max(gesture.x, gesture.brush)), from = state.panStart + Math.round(f0 * state.zoomLength) - 1, to = state.panStart + Math.round(f1 * state.zoomLength) - 1;
            setRange(Math.max(minimum, to - Math.max(0, from) + 1), Math.max(0, from)); zoomedByBrush = true;
          } else if (event.type === "pointerup" && gesture && !gesture.pinched && !gesture.moved) {
            var now = performance.now();
            if (lastTap && now - lastTap.time < 320 && Math.hypot(event.clientX - lastTap.x, event.clientY - lastTap.y) < 25) { resetZoom(); lastTap = null; }
            else { selectAt(event); lastTap = { time: now, x: event.clientX, y: event.clientY }; }
          }
          gesture = null; drawControls();
          if (zoomedByBrush) { zoomedByBrush = false; drawStage(); }
        }
      }
      stage.onpointerup = stage.onpointercancel = finish;
      stage.ondblclick = function (event) { event.preventDefault(); resetZoom(); };
      stage.addEventListener("wheel", function (event) {
        if (event.ctrlKey || event.metaKey) { event.preventDefault(); var center = state.panStart + state.zoomLength / 2, length = state.zoomLength * Math.exp(event.deltaY * .01); setRange(length, center - length / 2); update(); }
        else if (state.zoomLength < n && (event.deltaX || event.shiftKey)) { event.preventDefault(); setRange(state.zoomLength, state.panStart + (event.deltaX || event.deltaY) / Math.max(1, stage.clientWidth) * state.zoomLength); update(); }
      }, { passive: false });
      update(); phone.showSheet("Points Graph", panel, { graph: true, leading: reset, cleanup: function () { pointers.clear(); gesture = null; } });
    }
    function changeTab(tab) { state.tab=tab; statsTab.classList.toggle("active",tab==="stats");pointsTab.classList.toggle("active",tab==="points");paint(); }
    statsTab.onclick=function(){changeTab("stats");}; pointsTab.onclick=function(){changeTab("points");};
    function nativeSection(title, rows, compare) {
      var group = el("section", "pr-native-section"), header = el("h3", "pr-native-section-title"), card = el("div", "pr-native-card");
      if (compare) header.append(el("span", "phone-result-badge won", "Me"), el("span", "", title), el("span", "phone-result-badge lost", "Opp"));
      else header.textContent = title;
      if (compare) header.classList.add("pr-comparison-heading");
      card.append(rows); group.append(header, card); return group;
    }
    function valueRow(label, value) { var row = el("div", "pr-value-row"); row.append(el("span", "", label), el("span", "pr-muted", value)); return row; }
    function splitRow(label, mn, md, on, od, count, subtitle) {
      var row = el("div", "pr-comparison-row"), title = el("div", "pr-comparison-title", label), line = el("div", "pr-split-line");
      var max = Math.max(mn, on, 1), mf = count ? mn / max : md > 0 ? mn / md : 0, of = count ? on / max : od > 0 ? on / od : 0;
      row.dataset.stat = label; row.append(title); if (subtitle) row.append(el("div", "pr-comparison-subtitle", subtitle));
      line.append(el("strong", "pr-split-value pr-me", count ? String(mn) : percent(mn, md)));
      var bar = el("div", "pr-split-bar");
      [["me", mf, mn, md], ["opp", of, on, od]].forEach(function (side) {
        var half = el("span", "pr-split-half " + side[0]), fill = el("i", ""); fill.style.width = Math.max(0, Math.min(1, side[1])) * 100 + "%"; half.append(fill);
        if (!count) half.append(el("b", "", side[3] > 0 ? side[2] + "/" + side[3] : "—")); bar.append(half);
      });
      line.append(bar, el("strong", "pr-split-value pr-opp", count ? String(on) : percent(on, od))); row.append(line); return row;
    }
    function insightRows(lines, symbol) {
      var rows = el("div", "pr-coach-lines"); lines.forEach(function (line) { var row = el("div", "pr-coach-line"); row.append(phone.icon(symbol), el("span", "", line)); rows.append(row); }); return rows;
    }
    function pulseSection(scoped, maxHR) {
      var hr = scoped.filter(function (p) { return p.heartRateBPM > 0; }); if (!hr.length) return null;
      var rows = el("div", "pr-pulse-content"), insights = window.DeuceMatePhoneCoaching.pulse(record, scoped, maxHR);
      if (insights.length) rows.append(insightRows(insights, "sparkles"));
      var colors = ["#007aff", "#34c759", "#ffcc00", "#ff9500", "#ff3b30"], zones = colors.map(function (_, i) { return { zone: i + 1, total: 0, wins: 0 }; });
      hr.forEach(function (p) { var ratio = p.heartRateBPM / maxHR, z = ratio <= .6 ? 0 : ratio <= .7 ? 1 : ratio <= .8 ? 2 : ratio <= .9 ? 3 : 4; zones[z].total++; if (p.winner === "me") zones[z].wins++; });
      function svgChart(label, height) { var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("viewBox", "0 0 330 " + height); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", label); svg.classList.add("pr-pulse-chart"); return svg; }
      function mark(svg, tag, attrs, text) { var n = document.createElementNS("http://www.w3.org/2000/svg", tag); Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); }); if (text != null) n.textContent = text; svg.append(n); return n; }
      rows.append(el("h4", "pr-pulse-caption", "Win Rate by HR Zone"));
      var svg = svgChart("Win Rate by HR Zone", 180), present = zones.filter(function (z) { return z.total; });
      [0, 50, 100].forEach(function (value) { var y = 141 - value * 1.2; mark(svg, "line", { x1: 0, x2: 299, y1: y, y2: y, stroke: "#ffffff25" }); mark(svg, "text", { x: 302, y: y + 3, fill: "#98989e", "font-size": 10 }, value + "%"); });
      present.forEach(function (z, i) {
        var width = 299 / present.length, x = width * (i + .5), value = z.wins / z.total * 100, high = maxHR * ([.6, .7, .8, .9, 1][z.zone - 1]), low = z.zone === 1 ? 0 : Math.floor(maxHR * ([.6, .7, .8, .9][z.zone - 2])) + 1;
        mark(svg, "rect", { x: x - width * .3, y: 141 - value * 1.2, width: width * .6, height: value * 1.2, fill: colors[z.zone - 1], rx: 2 });
        mark(svg, "text", { x: x, y: 135 - value * 1.2, "text-anchor": "middle", fill: "#98989e", "font-size": 10 }, z.wins + "/" + z.total);
        mark(svg, "text", { x: x, y: 156, "text-anchor": "middle", fill: "#98989e", "font-size": 10 }, "Z" + z.zone);
        mark(svg, "text", { x: x, y: 168, "text-anchor": "middle", fill: "#98989e", "font-size": 8 }, z.zone === 1 ? "≤" + Math.floor(high) : z.zone === 5 ? low + "+" : low + "–" + Math.floor(high));
      }); rows.append(svg, el("h4", "pr-pulse-caption", "Heart Rate Through Match"));
      rows.append(phone.segment("Heart rate through match", state.pulseMode || "snapshot", [["snapshot", "Raw"], ["averaged", "Per-point avg"], ["smoothed", "Smoothed"]], function (v) { state.pulseMode = v; paint(); }));
      var timeline = svgChart("Heart Rate Through Match", 160), bpm = hr.map(function (p) { return p.heartRateBPM; }), lo = Math.max(40, Math.min.apply(null, bpm) - 10), hi = Math.max.apply(null, bpm) + 10;
      function y(value) { return 145 - (value - lo) / (hi - lo || 1) * 135; }
      [0, .6, .7, .8, .9].forEach(function (edge, i) { var low = Math.max(lo, maxHR * edge), high = Math.min(hi, maxHR * ([.6, .7, .8, .9, 2][i])); if (high <= low) return; mark(timeline, "rect", { x: 28, y: y(high), width: 276, height: y(low) - y(high), fill: colors[i], opacity: .18 }); mark(timeline, "text", { x: 308, y: y((low + high) / 2) + 3, fill: colors[i], "font-size": 10 }, "Z" + (i + 1)); });
      [0, .5, 1].forEach(function (f) { var value = Math.round(lo + (hi - lo) * f); mark(timeline, "text", { x: 0, y: y(value) + 3, fill: "#98989e", "font-size": 10 }, value); });
      var line = hr.map(function (p, i) { var radius = state.pulseMode === "smoothed" ? 2 : state.pulseMode === "averaged" ? 1 : 0, window = hr.slice(Math.max(0, i - radius), i + radius + 1), avg = window.reduce(function (sum, q) { return sum + q.heartRateBPM; }, 0) / window.length; return (28 + i / Math.max(1, hr.length - 1) * 276) + "," + y(avg); });
      mark(timeline, "polyline", { points: line.join(" "), fill: "none", stroke: "#f2f2f7", "stroke-width": 1.5 }); rows.append(timeline);
      if (state.pulseMode === "averaged") rows.append(phone.note("Per-point averages are simulated from recorded samples; this demo does not fetch Health data."));
      return nativeSection("Pulse Coach", rows);
    }
    function paintStats() {
      var wrap = el("div", "pr-stats"), scoped = filtered(), a = statsFor(scoped, "me"), b = statsFor(scoped, "opponent"), categorized = scoped.filter(function (p) { return p.outcome !== "uncategorized"; });
      if (!pts.length) { wrap.append(nativeSection("Statistics", phone.note("No point-by-point statistics were recorded for this match."))); return wrap; }
      if ((record.sets || []).length > 1) setFilter(wrap);
      var duration = el("div", ""), elapsed = record.setElapsed || {}, indices = (record.sets || []).map(function (_, i) { return i; }).filter(function (i) { return state.set === "all" || Number(state.set) === i; });
      indices.forEach(function (i) { var seconds = elapsed[i]; if (seconds == null && record.sets.length === 1) seconds = record.elapsed; if (seconds != null) duration.append(valueRow(indices.length > 1 ? setName(i) + " Duration" : "Duration", fmtDuration(seconds))); });
      var activity = activitySplit(record), steps = state.set === "all" ? record.steps : activity.steps[Number(state.set)], calories = state.set === "all" ? record.kcal : activity.calories[Number(state.set)];
      if (steps > 0) duration.append(valueRow("Steps", Math.round(steps).toLocaleString())); if (calories > 0) duration.append(valueRow("Calories", Math.round(calories).toLocaleString() + " kcal"));
      if (duration.childElementCount) wrap.append(nativeSection("Duration", duration));
      var insights = window.DeuceMatePhoneCoaching.rec(record, pts, scoped, state.set), coachTitle = "Coaching Insights" + (state.set === "all" ? "" : " · " + setName(Number(state.set)));
      if (insights.length) wrap.append(nativeSection(coachTitle, insightRows(insights.slice(0, 3), "tennis")));
      else if (categorized.length > 0 && categorized.length < 20) wrap.append(nativeSection(coachTitle, phone.note("Track " + (20 - categorized.length) + " more points to unlock coaching insights.")));
      var settings = phone.settings || {}, year = new Date().getFullYear(), birth = Number(settings.birthYear || 0), age = year - birth, override = !!settings.override && settings.overrideBpm >= 120 && settings.overrideBpm <= 220, maxHR = override ? Number(settings.overrideBpm) : birth > 1900 && age >= 5 && age <= 100 ? 220 - age : 190;
      var pulse = pulseSection(scoped, maxHR); if (pulse) wrap.append(pulse);
      function comparisons(title, rows) { var body = el("div", "pr-comparisons"); rows.forEach(function (r) { body.append(r); }); wrap.append(nativeSection(title, body, true)); }
      function ratioRow(label, mn, md, on, od, sub) { return splitRow(label, mn, md, on, od, false, sub); }
      if (categorized.length) {
        function wue(n, d) { return d > 0 ? (n / d).toFixed(1) + " : 1" : n > 0 ? "∞ : 1" : "—"; }
        var wueRow = el("div", "pr-wue-row"), label = el("span", "", "Win : Unforced Err"), values = el("span", ""); label.append(el("small", "pr-muted", "aim for > 1.0")); values.append(el("span", "pr-me", wue(a.myWinners, a.myUnforcedErrors)), el("span", "pr-muted", " / "), el("span", "pr-opp", wue(b.myWinners, b.myUnforcedErrors))); wueRow.append(label, values);
        comparisons("Outcome Breakdown", [wueRow,
          splitRow("Winners", a.myWinners, 0, b.myWinners, 0, true), splitRow("Unforced Errors", a.myUnforcedErrors, 0, b.myUnforcedErrors, 0, true), splitRow("Forced Errors", a.myForcedErrors, 0, b.myForcedErrors, 0, true), splitRow("Double Faults", a.myDoubleFaults, 0, b.myDoubleFaults, 0, true),
          ratioRow("Aggression Index", a.myWinners, a.myWinners + a.myUnforcedErrors, b.myWinners, b.myWinners + b.myUnforcedErrors, "W ÷ (W + UE)"), ratioRow("Own Errors %", a.myDoubleFaults + a.myUnforcedErrors, a.lostPoints, b.myDoubleFaults + b.myUnforcedErrors, b.lostPoints)]);
      } else wrap.append(nativeSection("Outcome Breakdown", phone.note("Outcome tracking not collected for this match.")));
      if (categorized.length === scoped.length && scoped.length) {
        comparisons("Serve", [ratioRow("1st Serve In", a.firstServeIn, a.firstServeTotal, b.firstServeIn, b.firstServeTotal), ratioRow("2nd Serve In", a.secondServeIn, a.secondServeTotal, b.secondServeIn, b.secondServeTotal), ratioRow("1st Serve Win", a.firstServeWins, a.firstServeIn, b.firstServeWins, b.firstServeIn), ratioRow("2nd Serve Win", a.secondServeWins, a.secondServeIn, b.secondServeWins, b.secondServeIn), ratioRow("DF Rate (2nd)", a.doubleFaults, a.secondServeTotal, b.doubleFaults, b.secondServeTotal)]);
        comparisons("Return", [ratioRow("vs 1st Serve", a.returnWinsOnFirst, a.returnOppsOnFirst, b.returnWinsOnFirst, b.returnOppsOnFirst), ratioRow("vs 2nd Serve", a.returnWinsOnSecond, a.returnOppsOnSecond, b.returnWinsOnSecond, b.returnOppsOnSecond)]);
      }
      comparisons("Break Points", [ratioRow("BPs Won (Returner)", a.breakPointWins, a.breakPointOpps, b.breakPointWins, b.breakPointOpps), ratioRow("BPs Saved (Server)", a.breakPointsFaced - a.breakPointsLost, a.breakPointsFaced, b.breakPointsFaced - b.breakPointsLost, b.breakPointsFaced)]);
      if (a.bigPointTotal > 0 && a.normalPointTotal > 0) comparisons("Pressure vs Normal", [ratioRow("Big Points", a.bigPointWins, a.bigPointTotal, b.bigPointWins, b.bigPointTotal), ratioRow("Normal Points", a.normalPointWins, a.normalPointTotal, b.normalPointWins, b.normalPointTotal)]);
      if (a.rallyDepth.length) comparisons("Rally Depth Won", a.rallyDepth.map(function (r) { var opp = b.rallyDepth.find(function (o) { return o.shot === r.shot; }) || { wins: 0, total: 0 }; return ratioRow("@ " + labelShot(r.shot), r.wins, r.total, opp.wins, opp.total); }));
      if (a.scoreStates.length) comparisons("Score States", a.scoreStates.map(function (r) { var opp = b.scoreStates.find(function (o) { return o.label === r.label; }) || { wins: 0, total: 0 }; return ratioRow(r.label, r.wins, r.total, opp.wins, opp.total); }));
      if (a.uncategorizedCount) wrap.append(phone.note(a.uncategorizedCount + " uncategorized point(s) excluded from outcome stats."));
      return wrap;
    }
    function paintPoints() {
      var wrap = el("div", "pr-points"); wrap.setAttribute("aria-label", "Point by point");
      (record.sets || []).forEach(function (_, setIndex) {
        var list = el("div", "pr-point-list"), points = pts.filter(function (p) { return Number(p.setIndex || 0) === setIndex; }); if (!points.length) return;
        points.forEach(function (p, i) {
          var original = pts.indexOf(p), row = phone.button("", function () { state.selected = original; drawGraph(); graphSection.scrollIntoView({ block: "nearest" }); }, "pr-point-row"), main = el("span", "pr-point-main");
          var before = timeline && timeline[original] ? timeline[original].before : ""; if (before) main.append(el("small", "pr-point-match-score", before));
          main.append(el("span", "pr-point-service", (p.server === "me" ? "🎾 Serving" : "Receiving") + (gameScoreBeforeLabel(p) ? " · " + gameScoreBeforeLabel(p) : "") + (p.isBreakPoint ? " · BP" : "") + (p.isSecondServe ? " · 2nd" : "")));
          var winner = p.winner === "me", fault = p.outcome === "doubleFault", actor = p.outcome === "winner" || p.outcome === "uncategorized" ? winner ? "Me" : "Opp" : winner ? "Opp" : "Me";
          var chip = el("b", "phone-result-badge " + ((p.outcome === "winner" || p.outcome === "uncategorized" ? winner : !winner) ? "won" : "lost"), ({ winner: winner ? "W" : "Opp W", forcedError: "FE", unforcedError: "UE", doubleFault: "DF", uncategorized: winner ? "+" : "−" })[p.outcome] || "+");
          var outcome = el("span", "pr-point-outcome"); outcome.append(chip, document.createTextNode(labelOutcome(p.outcome) + " — " + actor)); main.append(outcome);
          var health = el("span", "pr-point-health"); if (p.endingShot) health.append(el("small", "", labelShot(p.endingShot))); if (p.heartRateBPM != null) health.append(el("small", "", "My HR: " + p.heartRateBPM + " bpm")); var steps = pointSteps(pts, original); if (steps != null) health.append(el("small", "", steps + " steps"));
          row.append(el("span", "pr-point-index", String(i + 1)), main, health); list.append(row);
        }); wrap.append(nativeSection(setName(setIndex), list));
      }); return wrap;
    }
    function paint(){drawPointsWon();content.replaceChildren(state.tab==="stats"?paintStats():paintPoints());}
    root.openShare = function () { openShareMenu(phone,record); };
    // Mirrors MatchDetailView.storageInfoRow: location + one action while paired, then iCloud status.
    var storage = el("div", "pr-storage-info"), connection = phone.connection || {}, where = phone.storageLabel(record);
    if (connection.paired) {
      var line = el("div", "pr-storage-line"), text = el("span", "pr-storage-label"), action = null;
      if (where === "On Apple Watch only") { text.append(phone.icon("watch"), document.createTextNode("Saved on Apple Watch only")); action = ["Sync to iPhone", "good", function () { phone.recordActions(record); }]; }
      else if (where === "iPhone only") { text.append(phone.icon("phone"), document.createTextNode("Saved on iPhone only")); action = ["Sync to Watch", "good", function () { phone.syncToWatch(record); }]; }
      else { text.append(phone.icon("watch"), document.createTextNode("Saved on Apple Watch & iPhone")); action = ["Remove from Watch", "warn", function () { phone.removeFromWatch(record); }]; }
      var act = phone.button(action[0], action[2], "pr-storage-action " + action[1]); line.append(text, act); storage.append(line);
    }
    var cloud = phone.cloudStatus(), cloudLine = el("div", "pr-storage-line pr-storage-cloud" + (/unavailable/.test(cloud) ? " warn" : ""));
    cloudLine.append(el("span", "pr-storage-label", cloud)); storage.append(cloudLine);
    scroll.append(nativeSection("Storage Info", storage));
    drawGraph();paint();return root;
  }

  function openAI(phone, record, pts, focal, skipDisclosure) {
    var prompt = reportText(record, record.stats || pts, focal, "ai", phone.settings.playerNTRP);
    var fields=exportFields(record,"me",true);
    function present() {
      var panel = el("div", "pr-ai-sheet"), info = el("div", "pr-ai-card"), title = el("div", "pr-ai-intro-title");
      title.append(phone.icon("sparkles"), el("h3", "", "Get AI Coaching Tips"));
      info.append(title, el("p", "", "Send your match stats to an AI for personalised coaching feedback.")); panel.append(info);
      if ((record.stats || []).length) {
        var perspective = el("div", "pr-ai-perspective");
        perspective.append(phone.segment("Perspective", focal, [["me", "My Stats"], ["opponent", "Opponent's"]], function (value) { openAI(phone, record, pts, value, true); }));
        panel.append(perspective, el("p", "phone-note pr-ai-perspective-note", focal === "me" ? "Coaching tips for your own performance." : "Generate a prompt to share with your opponent — coaching for their side of the match."));
      }
      panel.append(el("h3", "phone-section-title", "Open in AI App"));
      var apps = el("div", "pr-ai-app-list"), handoff = el("p", "pr-ai-handoff"); handoff.setAttribute("role", "status");
      [["ChatGPT", "#8e8e93", "sparkles"], ["Claude", "#d99a70", "sparkles"], ["Gemini", "#4285f4", "sparkles"], ["Perplexity", "#20b9bb", "score"], ["Copilot", "#8c7df5", "sparkles"], ["Poe", "#b293ff", "score"], ["Grok", "#a0a0a5", "sparkles"]].forEach(function (app) {
        var b = phone.button("", function () { copyPrompt(promptField,true); handoff.textContent = "Would open " + app[0] + " here — this is a demo. No match data was sent."; phone.notify("Demo stub: no AI app was opened and no match data was sent"); }, "pr-ai-app-row");
        b.setAttribute("aria-label", "Open in " + app[0]);
        var tile = el("span", "pr-ai-app-icon"); tile.style.setProperty("--app-tint", app[1]); tile.append(phone.icon(app[2]));
        b.append(tile, el("span", "pr-ai-app-name", "Open in " + app[0]), el("span", "pr-ai-demo-badge", "Demo"), el("span", "pr-ai-app-arrow", "↗")); apps.append(b);
      });
      panel.append(apps, handoff, el("p", "phone-note", "These are demo hand-offs. No AI app is opened and no match data is sent."));
      var promptField = el("textarea", "pr-prompt"); promptField.value = prompt; promptField.readOnly = true; promptField.setAttribute("aria-label", "AI coaching prompt");
      var preview = el("details", "pr-ai-prompt-preview"); preview.append(el("summary", "", "Preview coaching prompt"), promptField);
      function manualCopy(field,quiet) {
        preview.open = true;
        field.focus(); field.select(); if(!quiet)phone.notify("Copy is unavailable; select and copy the prompt above");
      }
      function copyPrompt(field,quiet) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          try { navigator.clipboard.writeText(prompt).then(function () { if(!quiet)phone.notify("Prompt copied"); }, function () { manualCopy(field,quiet); }); }
          catch (_) { manualCopy(field,quiet); }
        } else manualCopy(field,quiet);
      }
      panel.append(el("h3", "phone-section-title", "Other"));
      var other = el("div", "pr-ai-other"), copy = phone.button("", function () { copyPrompt(promptField); }, "pr-ai-other-row");
      copy.setAttribute("aria-label", "Copy Prompt"); copy.append(phone.icon("copy"), el("span", "", "Copy Prompt to Clipboard"));
      var share = phone.button("", function () {
        var options = el("div", "pr-ai-share-options");
        options.append(phone.note("Save the coaching prompt to share with your preferred AI app."), phone.button("Download Prompt", function () { if (phone.download(fileBase(record) + (focal === "opponent" ? "-opponent" : "") + "_ai.txt", "text/plain;charset=utf-8", prompt)) { phone.closeSheet(); phone.notify("Prompt downloaded"); } }), phone.button("Back to AI Coach", present));
        phone.showSheet("Share AI Prompt", options, { presentation: "actions" });
      }, "pr-ai-other-row"); share.append(phone.icon("share"), el("span", "", "More Share Options…"));
      other.append(copy, share); panel.append(other, el("p", "phone-note", "Use any of these if your preferred AI app isn't listed above."), preview);
      if (phone.showSheet) phone.showSheet("AI Coach", panel);
    }
    if (fields.length && !skipDisclosure) {
      healthDisclosure(phone,fields,"Continue",present);
    } else present();
  }

  function trends(phone) { return window.DeuceMatePhoneTrends.render(phone); }

  window.DeuceMatePhoneReports = { detail: detail, detailTitle: detailTitle, trends: trends, standaloneHTML: standaloneHTML, reportText: reportText, exportModel: exportModel, scoreTimeline: scoreTimeline, score: score, openAI: openAI, openBrowserExports: openBrowserExports, exportFields: exportFields, activitySplit: activitySplit, graphSymbol: graphSymbol, graphSelection: graphSelection, graphSteps: graphSteps };
}());
