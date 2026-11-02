/* Pure browser port of Core's RecCoachInsights and PulseCoachInsights. */
(function (root) {
  "use strict";

  function pct(value) { return Math.round(value * 100); }
  function otherPlayer(focal) { return focal === "opponent" ? "me" : "opponent"; }
  function categorized(points) { return points.filter(function (point) { return point.outcome !== "uncategorized"; }); }
  function count(points, predicate) { return points.reduce(function (total, point) { return total + (predicate(point) ? 1 : 0); }, 0); }
  function winRate(points, focal) { return points.length ? count(points, function (point) { return point.winner === focal; }) / points.length : 0; }
  function indexOfSetFilter(setFilter) {
    if (setFilter == null || setFilter === "all" || setFilter === "All Sets") return null;
    if (typeof setFilter === "number" && Number.isInteger(setFilter) && setFilter >= 0) return setFilter;
    var match = String(setFilter).match(/(?:set[- ]?)?(\d+)$/i);
    if (!match) return null;
    var value = Number(match[1]);
    // UI filters use zero-based values; support human-readable "Set N" too.
    return /^set\s*\d+$/i.test(String(setFilter)) ? value - 1 : value;
  }
  function timestampValue(point) {
    var value = point && point.timestamp;
    if (value instanceof Date) return value.getTime();
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string") {
      var parsed = Date.parse(value);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  }
  function chronological(points) {
    var allHaveTime = points.every(function (point) { return timestampValue(point) != null; });
    return points.map(function (point, index) { return { point: point, index: index, time: timestampValue(point) }; })
      .sort(function (a, b) { return allHaveTime && a.time !== b.time ? a.time - b.time : a.index - b.index; })
      .map(function (entry) { return entry.point; });
  }
  function serviceGames(points, focal) {
    var games = 0, inFocalGame = false;
    chronological(points).forEach(function (point) {
      if (point.server === focal) {
        if (!inFocalGame) inFocalGame = true;
      } else if (inFocalGame) {
        games += 1;
        inFocalGame = false;
      }
    });
    if (inFocalGame) games += 1;
    return games;
  }
  function roundedMean(values) {
    return values.length ? Math.floor(values.reduce(function (a, b) { return a + b; }, 0) / values.length + 0.5) : 0;
  }

  function rec(record, points, scopedPoints, setFilter, focal, allowHealth) {
    var all = Array.isArray(points) ? points : (record && record.stats) || [];
    var me = focal === "opponent" ? "opponent" : "me";
    var selected = indexOfSetFilter(setFilter);
    var scoped = Array.isArray(scopedPoints) ? scopedPoints : selected == null ? all : all.filter(p => p.setIndex === selected);
    var cat = categorized(scoped);
    if (cat.length < 20) return [];
    var candidates = [];
    function add(id, score, topics, line) { candidates.push({id, score, topics, line}); }
    function covered(known, full) { return full.length > 0 && known.length / full.length >= 0.8; }
    function firstIn(p) { return !p.isSecondServe && p.outcome !== "doubleFault"; }
    function rate(ps) { return winRate(ps, me); }
    function fraction(ps) { return pct(rate(ps)) + "% (" + count(ps,p=>p.winner===me) + "/" + ps.length + ")"; }
    var serves = cat.filter(p=>p.server===me), returns = cat.filter(p=>p.server!==me);
    var serveCoverage = covered(serves,scoped.filter(p=>p.server===me));
    var returnCoverage = covered(returns,scoped.filter(p=>p.server!==me));
    var faults = cat.filter(p=>p.server===me && p.winner!==me && p.outcome==="doubleFault");
    var breaks = count(faults,p=>p.isBreakPoint && !(p.gameScoreAtStart && p.gameScoreAtStart.isTiebreak));
    if (breaks > 0) {
      var context = faults.length===1 ? "1 double fault on break point" : faults.length + " double faults, including " + breaks + " on break point" + (breaks===1?"":"s");
      add("doubleFaults",32+Math.min(breaks,5),["serveReliability","errors","pressureServe"],context+" — practise your second-serve routine under pressure.");
    } else if (serveCoverage) {
      var games=0,previous=null;
      chronological(scoped).forEach(p=>{
        var g=p.gameScoreAtStart;
        if(p.server===me && !(g&&g.isTiebreak) && (!previous||previous.server!==me||previous.setIndex!==p.setIndex||(g&&g.server===0&&g.returner===0))) games++;
        previous=p;
      });
      var regularFaults=count(faults,p=>!(p.gameScoreAtStart&&p.gameScoreAtStart.isTiebreak));
      if(regularFaults>=3&&games>=4&&regularFaults/games>=0.5) add("doubleFaults",18+Math.min(regularFaults,12),["serveReliability","errors"],regularFaults+" double faults in "+games+" service games — practise a repeatable second-serve routine.");
    }
    var first=serves.filter(firstIn),second=serves.filter(p=>p.isSecondServe&&p.outcome!=="doubleFault");
    if(serveCoverage) {
      var inRate=serves.length?first.length/serves.length:0;
      if(serves.length>=30&&inRate<0.5) {
        var seconds=serves.filter(p=>!firstIn(p)),weak=seconds.length>=8&&rate(seconds)<0.45;
        add("firstServe",10+(0.5-inRate)*Math.min(serves.length,30)+(weak?14:0),weak?["serveReliability","secondServe"]:["serveReliability"],
          "First serves in: "+pct(inRate)+"% ("+first.length+"/"+serves.length+")"+(weak?"; second-serve points won: "+fraction(seconds):"")+" — "+(weak?"try slightly less pace or a familiar spin serve.":"test a larger target and compare your service-point results."));
      }
      var gap=rate(first)-rate(second);
      if(first.length>=8&&second.length>=8&&gap>=0.2) add("secondServe",10+gap*Math.min(first.length,second.length,30),["secondServe"],"Points won: "+fraction(first)+" on first serve vs "+fraction(second)+" on second serves in play — review spin, placement and next-shot preparation.");
    }
    var balance=rate(serves)-rate(returns);
    if(serveCoverage&&returnCoverage&&serves.length>=20&&returns.length>=20&&balance>=0.25) add("serveReturn",8+balance*Math.min(serves.length,returns.length,30),["returnPlay"],"Points won: "+fraction(serves)+" serving vs "+fraction(returns)+" receiving — review returns and following rallies; the gap alone does not explain why.");
    if(returnCoverage) {
      var known=returns.filter(p=>p.endingShot!=null);
      if(covered(known,returns)) {
        var attempts=known.filter(p=>p.endingShot!=="serve"&&p.outcome!=="doubleFault");
        var misses=count(attempts,p=>p.winner!==me&&p.outcome==="unforcedError"&&p.endingShot==="return");
        if(attempts.length>=10&&misses>=3&&misses/attempts.length>=0.25) add("missedReturns",18+Math.min(misses,15),["returnPlay","errors"],misses+"/"+attempts.length+" tracked return attempts ended in an unforced error — review return position, split-step timing and preparation.");
        var returnLosses=known.filter(p=>p.winner!==me);
        var rallyErrors=count(returnLosses,p=>p.outcome==="unforcedError"&&(p.endingShot==="servePlusOne"||p.endingShot==="rally"));
        if(returnLosses.length>=10&&rallyErrors/returnLosses.length>=0.4) add("returnRallyErrors",16+Math.min(rallyErrors,15),["returnPlay","errors","rally"],rallyErrors+"/"+returnLosses.length+" tracked losses while receiving were unforced errors after the return — review recovery position, spacing and shot selection.");
      }
    }
    var lost=cat.filter(p=>p.winner!==me),errors=count(lost,p=>p.outcome==="unforcedError"||(p.outcome==="doubleFault"&&p.server===me));
    if(cat.length>=25&&lost.length>=15&&covered(lost,scoped.filter(p=>p.winner!==me))&&errors/lost.length>=0.55) add("ownErrors",4+errors/lost.length*15,["errors","rally"],pct(errors/lost.length)+"% of classified losses were unforced errors or double faults ("+errors+"/"+lost.length+") — review preparation, spacing and shot selection.");
    [true,false].forEach(serving=>{
      var side=cat.filter(p=>(p.server===me)===serving),known=side.filter(p=>p.isBreakPoint||p.gameScoreAtStart!=null);
      if(!covered(known,scoped.filter(p=>(p.server===me)===serving))) return;
      function isPressure(p) {var g=p.gameScoreAtStart;return p.isBreakPoint||!!g&&(g.isTiebreak||(g.server>=3&&g.returner>=3));}
      var big=known.filter(isPressure),ordinary=known.filter(p=>!isPressure(p)),gap=rate(ordinary)-rate(big);
      if(big.length>=8&&ordinary.length>=15&&gap>=0.2) add(serving?"pressureServe":"pressureReturn",10+gap*Math.min(big.length,ordinary.length,30),["pressure",serving?"pressureServe":"returnPlay"],(serving?"Serving":"Receiving")+": "+fraction(big)+" points won under pressure vs "+fraction(ordinary)+" otherwise — use your usual routine and a clear target.");
    });
    var knownServe=cat.filter(p=>p.server===me&&p.endingShot!=null);
    if(covered(knownServe,scoped.filter(p=>p.server===me))) {
      var early=knownServe.filter(p=>p.endingShot==="servePlusOne"),late=knownServe.filter(p=>p.endingShot==="rally"),gap=rate(early)-rate(late);
      if(early.length>=8&&late.length>=8&&gap>=0.15) add("rallies",6+gap*Math.min(early.length,late.length,25),["rally"],"On serve, you won "+fraction(early)+" points ending at Serve+1 vs "+fraction(late)+" in the rally phase — review how rallies were lost before changing tactics.");
    }
    var laterSets=selected==null?Array.from(new Set(all.map(p=>p.setIndex))).filter(i=>i>0).sort((a,b)=>a-b):selected>0?[selected]:[];
    laterSets.forEach(later=>{
      var earlier=later-1,firstAll=all.filter(p=>p.setIndex===earlier),secondAll=all.filter(p=>p.setIndex===later);
      var firstLost=categorized(firstAll).filter(p=>p.winner!==me),secondLost=categorized(secondAll).filter(p=>p.winner!==me);
      var r1=firstLost.length?count(firstLost,p=>p.outcome==="unforcedError")/firstLost.length:0,r2=secondLost.length?count(secondLost,p=>p.outcome==="unforcedError")/secondLost.length:0;
      var rise=firstLost.length>=12&&secondLost.length>=12&&r2-r1>=0.1&&r2>=0.25&&covered(firstLost,firstAll.filter(p=>p.winner!==me))&&covered(secondLost,secondAll.filter(p=>p.winner!==me));
      var durations=record&&record.setElapsed||{},duration=durations[earlier]||0,drop=rate(firstAll)-rate(secondAll);
      var decline=duration>=1800&&durations[later]!=null&&firstAll.length>=20&&secondAll.length>=20&&drop>=0.15;
      if(!rise&&!decline)return;
      var facts=[];
      if(rise)facts.push("Unforced errors rose from "+pct(r1)+"% in set "+(earlier+1)+" to "+pct(r2)+"% in set "+(later+1)+" as a share of classified losses");
      if(decline)facts.push((rise?"points won fell":"After a "+Math.floor(duration/60)+"-minute set "+(earlier+1)+", points won fell")+" from "+pct(rate(firstAll))+"% to "+pct(rate(secondAll))+"% in set "+(later+1));
      add("setChange"+later,8+Math.max(rise?r2-r1:0,decline?drop:0)*25,rise?["setChange","errors"]:["setChange"],facts.join("; ")+" — review preparation, positioning and shot selection.");
    });
    if(allowHealth!==false&&me==="me"&&record&&record.matchType==="singles") {
      var ordered=chronological(scoped),movement=[],heartRate=[];
      function consecutive(a,b) {
        var x=a.gameScoreAtStart,y=b.gameScoreAtStart,dt=timestampValue(b)-timestampValue(a);
        if(a.server!=="me"||b.server!=="me"||a.setIndex!==b.setIndex||!x||!y||x.isTiebreak||y.isTiebreak||timestampValue(a)==null||timestampValue(b)==null||!(dt>0&&dt<=90000))return false;
        var server=x.server+(a.winner==="me"?1:0),returner=x.returner+(a.winner==="me"?0:1);
        if(Math.max(server,returner)>=4&&Math.abs(server-returner)>=2)return false;
        return y.server===server&&y.returner===returner;
      }
      for(var i=1;i<ordered.length;i++) {
        var previous=ordered[i-1],next=ordered[i];
        if(!consecutive(previous,next)||previous.outcome==="uncategorized"||next.outcome==="uncategorized")continue;
        if(previous.heartRateBPM>0)heartRate.push({next,load:previous.heartRateBPM});
        if(i>=2){var before=ordered[i-2];if(consecutive(before,previous)&&before.outcome!=="uncategorized"&&before.stepsCumulative!=null&&previous.stepsCumulative!=null&&before.stepsCumulative>=0&&previous.stepsCumulative>=before.stepsCumulative)movement.push({next,load:previous.stepsCumulative-before.stepsCumulative});}
      }
      function effort(samples,label,id,separation) {
        if(samples.length<20)return;
        var sorted=samples.map(x=>x.load).sort((a,b)=>a-b),middle=Math.floor(sorted.length/2),median=sorted.length%2?sorted[middle]:(sorted[middle-1]+sorted[middle])/2;
        var high=samples.filter(x=>x.load>median),low=samples.filter(x=>x.load<=median);
        if(high.length<10||low.length<10)return;
        var mean=xs=>xs.reduce((s,x)=>s+x.load,0)/xs.length;
        if(mean(high)-mean(low)<separation)return;
        var hp=high.map(x=>x.next),lp=low.map(x=>x.next),hi=count(hp,firstIn)/hp.length,li=count(lp,firstIn)/lp.length;
        var hd=count(hp,p=>p.outcome==="doubleFault"&&p.winner!=="me"),ld=count(lp,p=>p.outcome==="doubleFault"&&p.winner!=="me"),rise=hd/hp.length-ld/lp.length,drop=rate(lp)-rate(hp),weight=Math.min(high.length,low.length,30);
        var advice=" — practise resetting your breathing and serve routine between points.";
        if(li-hi>=0.15)add(id+"FirstServe",20+(li-hi)*weight,["exertion","serveReliability"],"First serves in after "+label+": "+pct(hi)+"% ("+count(hp,firstIn)+"/"+hp.length+") vs "+pct(li)+"% ("+count(lp,firstIn)+"/"+lp.length+") otherwise"+advice);
        if(hd>=3&&rise>=0.1)add(id+"DoubleFaults",20+rise*weight,["exertion","serveReliability","errors"],"Double faults after "+label+": "+hd+"/"+hp.length+" service points vs "+ld+"/"+lp.length+" otherwise"+advice);
        if(drop>=0.2)add(id+"ServicePoints",12+drop*weight,["exertion","serveResults"],"Service points won after "+label+": "+fraction(hp)+" vs "+fraction(lp)+" otherwise"+advice);
      }
      effort(movement,"higher-movement points","movement",5);
      effort(heartRate,"points with higher recorded heart rate","heartRate",10);
    }
    candidates.sort((a,b)=>b.score-a.score||(a.id<b.id?-1:a.id>b.id?1:0));
    var topics=new Set(),lines=[];
    candidates.forEach(c=>{if(lines.length<3&&!c.topics.some(t=>topics.has(t))){lines.push(c.line);c.topics.forEach(t=>topics.add(t));}});
    return lines;
  }

  function pulse(_record, points, maxHR, focal) {
    var me = focal === "opponent" ? "opponent" : "me";
    var samples = (Array.isArray(points) ? points : []).map(function (point, index) {
      var bpm = Number(point.heartRateBPM);
      return Number.isFinite(bpm) && bpm > 0 ? { point: point, bpm: bpm, index: index } : null;
    }).filter(Boolean);
    if (samples.length < 10) return [];
    var resolvedMax = Number(maxHR);
    var zones = [0, 0, 0, 0, 0].map(function () { return { total: 0, wins: 0 }; });
    samples.forEach(function (sample) {
      var zoneIndex;
      if (!(resolvedMax > 0)) zoneIndex = 0;
      else {
        var ratio = sample.bpm / resolvedMax;
        zoneIndex = ratio < 0.60 ? 0 : ratio < 0.70 ? 1 : ratio < 0.80 ? 2 : ratio < 0.90 ? 3 : 4;
      }
      zones[zoneIndex].total += 1;
      if (sample.point.winner === me) zones[zoneIndex].wins += 1;
    });
    var qualified = zones.map(function (zone, index) {
      return zone.total >= 5 ? { zone: index + 1, total: zone.total, rate: zone.wins / zone.total } : null;
    }).filter(Boolean);
    var lines = [];
    if (qualified.length >= 2) {
      var ordered = qualified.slice().sort(function (a, b) { return a.rate - b.rate || a.zone - b.zone; });
      var worst = ordered[0], best = ordered[ordered.length - 1];
      if (best.zone !== worst.zone && best.rate - worst.rate >= 0.15) {
        lines.push("You won " + pct(best.rate) + "% of points in Z" + best.zone + " but only " + pct(worst.rate) + "% in Z" + worst.zone + ".");
      }
    }

    var breakPoints = samples.filter(function (sample) { return sample.point.isBreakPoint; });
    if (breakPoints.length >= 4) {
      var hrValues = breakPoints.map(function (sample) { return sample.bpm; }).sort(function (a, b) { return a - b; });
      var middle = Math.floor(hrValues.length / 2);
      var median = hrValues.length % 2 ? hrValues[middle] : Math.floor((hrValues[middle - 1] + hrValues[middle]) / 2);
      var above = breakPoints.filter(function (sample) { return sample.bpm > median; });
      var losses = count(above, function (sample) { return sample.point.winner !== me; });
      if (above.length >= 2 && losses / above.length >= 0.6) {
        lines.push("You lost " + losses + " of " + above.length + " break points after HR rose above " + median + " bpm.");
      }
    }

    if (samples.length >= 20) {
      var allHaveTime = samples.every(function (sample) { return timestampValue(sample.point) != null; });
      var sorted = samples.slice().sort(function (a, b) {
        var ta = timestampValue(a.point), tb = timestampValue(b.point);
        return allHaveTime && ta !== tb ? ta - tb : a.index - b.index;
      });
      var half = Math.floor(sorted.length / 2), first = sorted.slice(0, half), second = sorted.slice(half);
      var firstRate = winRate(first.map(function (sample) { return sample.point; }), me);
      var secondRate = winRate(second.map(function (sample) { return sample.point; }), me);
      var firstAvg = first.reduce(function (sum, sample) { return sum + sample.bpm; }, 0) / first.length;
      var secondAvg = second.reduce(function (sum, sample) { return sum + sample.bpm; }, 0) / second.length;
      if (firstRate - secondRate >= 0.15 && secondAvg - firstAvg >= 10) {
        lines.push("Win rate dropped from " + pct(firstRate) + "% to " + pct(secondRate) + "% as average HR climbed by " + Math.floor(secondAvg - firstAvg + 0.5) + " bpm.");
      }
    }
    return lines.slice(0, 3);
  }

  root.DeuceMatePhoneCoaching = { rec: rec, pulse: pulse };
})(window);
