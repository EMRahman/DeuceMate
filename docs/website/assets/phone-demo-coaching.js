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

  function rec(record, points, scopedPoints, setFilter, focal) {
    var all = Array.isArray(points) ? points : (record && Array.isArray(record.stats) ? record.stats : []);
    var me = focal === "opponent" ? "opponent" : "me", other = otherPlayer(me);
    var setIndex = indexOfSetFilter(setFilter);
    var scoped = Array.isArray(scopedPoints) ? scopedPoints : (setIndex == null ? all : all.filter(function (p) { return Number(p.setIndex || 0) === setIndex; }));
    var cat = categorized(scoped);
    if (cat.length < 20) return [];
    var fullCat = categorized(all), lines = [];
    var earlier = setIndex == null ? 0 : setIndex - 1;
    var later = setIndex == null ? 1 : setIndex;
    var crossSet = setIndex == null || setIndex >= 1;

    // 1. Self-inflicted losses: ≥25 categorized points, ≥15 losses, ≥55% UE/DF.
    if (cat.length >= 25) {
      var lost = cat.filter(function (p) { return p.winner === other; });
      var selfInflicted = lost.filter(function (p) {
        return p.outcome === "unforcedError" || (p.outcome === "doubleFault" && p.server === me);
      });
      if (lost.length >= 15 && selfInflicted.length / lost.length >= 0.55) {
        lines.push(pct(selfInflicted.length / lost.length) + "% of points you lost were unforced errors or double faults (" + selfInflicted.length + "/" + lost.length + ") — reliability is your biggest lever.");
      }
    }

    // 2. UE-rate drift: ≥12 losses in each adjacent set; +10 points and later ≥25%.
    if (crossSet) {
      var earlierLost = fullCat.filter(function (p) { return p.setIndex === earlier && p.winner === other; });
      var laterLost = fullCat.filter(function (p) { return p.setIndex === later && p.winner === other; });
      var earlierUE = count(earlierLost, function (p) { return p.outcome === "unforcedError"; });
      var laterUE = count(laterLost, function (p) { return p.outcome === "unforcedError"; });
      var earlierRate = earlierLost.length ? earlierUE / earlierLost.length : 0;
      var laterRate = laterLost.length ? laterUE / laterLost.length : 0;
      if (earlierLost.length >= 12 && laterLost.length >= 12 && laterRate - earlierRate >= 0.10 && laterRate >= 0.25) {
        lines.push("Your unforced-error rate climbed from " + pct(earlierRate) + "% in set " + (earlier + 1) + " to " + pct(laterRate) + "% in set " + (later + 1) + " — fatigue may be changing your shot selection.");
      }
    }

    // 3. Double-fault leakage: ≥3 focal DFs, ≥4 focal service games, ≥0.5 DF/game.
    var dfs = count(cat, function (p) { return p.server === me && p.outcome === "doubleFault"; });
    var games = serviceGames(scoped, me);
    if (dfs >= 3 && games >= 4 && dfs / games >= 0.5) {
      lines.push(dfs + " double faults in " + games + " service games — each one is a free point at the worst time.");
    }

    // 4. Pressure-point drop: ≥8 big and ≥15 normal; normal win rate trails by 20pp.
    function isBig(point) {
      if (point.isBreakPoint) return true;
      var score = point.gameScoreAtStart;
      return !!score && (!!score.isTiebreak || (Number(score.server) >= 3 && Number(score.returner) >= 3));
    }
    var big = cat.filter(isBig), normal = cat.filter(function (p) { return !isBig(p); });
    var bigWinRate = winRate(big, me), normalWinRate = winRate(normal, me);
    if (big.length >= 8 && normal.length >= 15 && normalWinRate - bigWinRate >= 0.20) {
      lines.push("You won " + pct(normalWinRate) + "% of normal points but only " + pct(bigWinRate) + "% on big points (break/deuce/tiebreak) — try playing the same ball you'd hit at 0-0.");
    }

    // 5. Rally length: ≥8 Serve+1 and ≥8 rally endings; +15pp Serve+1 win rate.
    var withShot = scoped.filter(function (p) { return p.endingShot != null; });
    var servePlusOne = withShot.filter(function (p) { return p.endingShot === "servePlusOne"; });
    var rallies = withShot.filter(function (p) { return p.endingShot === "rally"; });
    var servePlusOneRate = winRate(servePlusOne, me), rallyRate = winRate(rallies, me);
    if (servePlusOne.length >= 8 && rallies.length >= 8 && servePlusOneRate - rallyRate >= 0.15) {
      lines.push("You won " + pct(servePlusOneRate) + "% of points ending by Serve+1 but only " + pct(rallyRate) + "% in long rallies — try to finish earlier.");
    }

    // 6. Second-serve vulnerability: ≥8 first-serve and ≥8 in-play second-serve points; -20pp.
    var serves = scoped.filter(function (p) { return p.server === me; });
    var firstServes = serves.filter(function (p) { return !p.isSecondServe; });
    var secondServes = serves.filter(function (p) { return p.isSecondServe && p.outcome !== "doubleFault"; });
    var firstRate = winRate(firstServes, me), secondRate = winRate(secondServes, me);
    if (firstServes.length >= 8 && secondServes.length >= 8 && firstRate - secondRate >= 0.20) {
      lines.push("You won " + pct(firstRate) + "% on 1st serve but only " + pct(secondRate) + "% on 2nd serve (" + secondServes.length + " points) — a slower, spin-heavy 2nd serve keeps you in the point.");
    }

    // 7. Return UEs: ≥10 return losses and ≥40% are unforced errors.
    var returnLosses = cat.filter(function (p) { return p.server === other && p.winner === other; });
    var returnUEs = count(returnLosses, function (p) { return p.outcome === "unforcedError"; });
    if (returnLosses.length >= 10 && returnUEs / returnLosses.length >= 0.40) {
      lines.push(pct(returnUEs / returnLosses.length) + "% of your return losses (" + returnUEs + "/" + returnLosses.length + ") were unforced errors — aim for a safe, deep crosscourt return instead of going for the lines.");
    }

    // 8. Set-duration decline: earlier set ≥30 min; ≥20 points/set; win-rate drop ≥15pp.
    if (crossSet) {
      var durations = (record && record.setElapsed) || {};
      var earlierDuration = Number(durations[earlier]);
      var laterDuration = Number(durations[later]);
      var earlyPoints = all.filter(function (p) { return p.setIndex === earlier; });
      var latePoints = all.filter(function (p) { return p.setIndex === later; });
      var earlyRate = winRate(earlyPoints, me), lateRate = winRate(latePoints, me);
      if (Number.isFinite(earlierDuration) && Number.isFinite(laterDuration) && earlierDuration >= 1800 &&
          earlyPoints.length >= 20 && latePoints.length >= 20 && earlyRate - lateRate >= 0.15) {
        lines.push("After a " + Math.floor(earlierDuration / 60 + 0.5) + "-minute set " + (earlier + 1) + ", your set " + (later + 1) + " win rate dropped from " + pct(earlyRate) + "% to " + pct(lateRate) + "%.");
      }
    }

    return lines.slice(0, 3);
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
