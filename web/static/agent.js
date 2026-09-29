(function () {
  if (window.__naverAgentActive) {
    alert('이미 실행 중입니다. 화면 하단 상태 표시를 확인하세요.');
    return;
  }
  if (location.hostname.indexOf('land.naver.com') === -1) {
    alert('new.land.naver.com 페이지에서 실행해 주세요.');
    return;
  }
  window.__naverAgentActive = true;

  var scriptSrc = (document.currentScript && document.currentScript.src) || '';
  var params = new URLSearchParams(scriptSrc.split('?')[1] || '');
  var SERVER = params.get('server');
  var SESSION_ID = params.get('session_id');

  if (!SERVER || !SESSION_ID) {
    alert('설정 오류: 서버 주소 또는 세션 ID가 없습니다. 북마클릿을 다시 만들어 주세요.');
    window.__naverAgentActive = false;
    return;
  }

  var origFetch = window.fetch.bind(window);
  var jwt = null;

  window.fetch = function (input, init) {
    try {
      var req = (typeof Request !== 'undefined' && input instanceof Request) ? input : new Request(input, init);
      var auth = req.headers.get('Authorization') || req.headers.get('authorization');
      if (auth && auth.indexOf('Bearer ') === 0) jwt = auth.slice(7);
    } catch (e) { /* 무시 — 인증 캡처는 부가 기능이라 실패해도 원래 fetch는 계속 진행 */ }
    return origFetch(input, init);
  };

  var box = document.createElement('div');
  box.id = '__naver_agent_box';
  box.style.cssText =
    'position:fixed;bottom:16px;left:16px;right:16px;z-index:2147483647;' +
    'background:#191F28;color:#fff;padding:14px 16px;border-radius:16px;' +
    'font:13px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.5;' +
    'box-shadow:0 6px 24px rgba(0,0,0,.35);';
  document.body.appendChild(box);
  function setStatus(msg) { box.textContent = '🤖 ' + msg; }
  setStatus('시작 중...');

  function apiPost(path, body) {
    return origFetch(SERVER + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then(function (r) { return r.json(); });
  }
  function apiGet(path) {
    return origFetch(SERVER + path).then(function (r) { return r.json(); });
  }
  function sleep(ms) { return new Promise(function (res) { setTimeout(res, ms); }); }

  function waitForJWT() {
    setStatus('인증정보 확보 중 — 지도를 손가락으로 살짝 움직여 주세요...');
    var tries = 0;
    return new Promise(function (resolve, reject) {
      var timer = setInterval(function () {
        tries++;
        if (jwt) { clearInterval(timer); resolve(); }
        else if (tries > 90) { clearInterval(timer); reject(new Error('인증정보(JWT)를 확보하지 못했습니다 — 지도를 움직여 보세요')); }
      }, 1000);
    });
  }

  function fetchAuthed(url) {
    return origFetch(url, {
      headers: {
        'Authorization': 'Bearer ' + jwt,
        'Accept': 'application/json',
        'Referer': 'https://new.land.naver.com/',
      },
    }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }

  function getCortar(lat, lon) {
    var zooms = [15, 14];
    var i = 0;
    function tryOne() {
      if (i >= zooms.length) return Promise.resolve(null);
      var zoom = zooms[i++];
      var url = 'https://new.land.naver.com/api/cortars?zoom=' + zoom + '&centerLat=' + lat + '&centerLon=' + lon;
      return fetchAuthed(url).then(function (d) { return d || tryOne(); });
    }
    return tryOne();
  }

  function listParams(cortarNo) {
    return 'cortarNo=' + cortarNo +
      '&realEstateType=APT%3AABYH%3AMLS' +
      '&tradeType=A1' +
      '&tag=RENTHUG%3A%3A%3A%3A%3A%3A%3A%3A' +
      '&rentPriceMin=0&rentPriceMax=900000000' +
      '&priceMin=0&priceMax=900000000' +
      '&areaMin=0&areaMax=900000000' +
      '&oldBuildYears&recentlyBuildYears&minHouseHoldCount&maxHouseHoldCount' +
      '&showArticle=false&sameAddressGroup=false' +
      '&minMaintenanceCost&maxMaintenanceCost&perPage=20';
  }

  function getArticleList(cortarNo, maxCount, onProgress) {
    var list = [];
    function nextPage(page) {
      if (list.length >= maxCount) return Promise.resolve(list);
      var url = 'https://new.land.naver.com/api/articles?' + listParams(cortarNo) + '&page=' + page;
      return fetchAuthed(url).then(function (result) {
        if (!result || !result.articleList || !result.articleList.length) return list;
        list = list.concat(result.articleList);
        onProgress(list.length);
        if (!result.isMoreData || list.length >= maxCount) return list;
        return sleep(100).then(function () { return nextPage(page + 1); });
      });
    }
    return nextPage(1);
  }

  var pyeongCache = {};
  var realPriceCache = {};

  function fillRentFallback(detail) {
    var addition = detail.articleAddition || {};
    var price = detail.articlePrice || {};
    var hasRent = !!addition.rentPrc || (price.rentPrice > 0) || (price.allWarrantPrice > 0);
    if (hasRent) return Promise.resolve(detail);

    var cno = String((detail.articleDetail || {}).hscpNo || '');
    if (!cno) return Promise.resolve(detail);

    var pyeongPromise = pyeongCache[cno] ||
      (pyeongCache[cno] = fetchAuthed('https://new.land.naver.com/api/complexes/' + cno + '?sameAddressGroup=false')
        .then(function (d) {
          return ((d && d.complexPyeongDetailList) || []).map(function (p) {
            return { pyeongNo: String(p.pyeongNo), exclusiveArea: parseFloat(p.exclusiveArea) || 0 };
          });
        }));

    return pyeongPromise.then(function (pyList) {
      if (!pyList.length) return detail;
      var space = detail.articleSpace || {};
      var ea = parseFloat(space.exclusiveSpace) || 0;
      var best = pyList[0];
      if (ea) {
        for (var i = 1; i < pyList.length; i++) {
          if (Math.abs(pyList[i].exclusiveArea - ea) < Math.abs(best.exclusiveArea - ea)) best = pyList[i];
        }
      }
      var rk = cno + ':' + best.pyeongNo;
      var rpPromise = realPriceCache[rk] ||
        (realPriceCache[rk] = fetchAuthed(
          'https://new.land.naver.com/api/complexes/' + cno + '/prices/real?tradeType=B1&areaNo=' + best.pyeongNo + '&type=table'
        ).then(function (d) {
          var months = (d && d.realPriceOnMonthList) || [];
          if (!months.length) return null;
          var rows = (months[0].realPriceList || []).slice();
          rows.sort(function (a, b) { return Number(b.tradeDate) - Number(a.tradeDate); });
          return rows[0] || null;
        }));
      return rpPromise.then(function (rp) {
        if (rp && rp.formattedPrice) {
          var dt = (rp.formattedTradeYearMonth || '').slice(0, 7) || new Date().toISOString().slice(0, 7).replace('-', '.');
          detail._fetched_rent_price = rp.formattedPrice + ' (' + dt + '. 거래내역)';
        }
        return detail;
      });
    });
  }

  function fetchArticleDetail(articleNo) {
    return fetchAuthed('https://new.land.naver.com/api/articles/' + articleNo);
  }

  function processBatch(batch) {
    return Promise.all(batch.map(function (a) {
      var no = String(a.articleNo || '');
      if (!no) return null;
      return fetchArticleDetail(no).then(function (detail) {
        if (!detail || !detail.articleDetail) return null;
        return fillRentFallback(detail).then(function (d) { return { article_no: no, detail: d }; });
      });
    })).then(function (results) { return results.filter(Boolean); });
  }

  function processRegion(jobId, region) {
    setStatus('[' + region.index + '/' + region.total + '] ' + region.name + ' — 지역 코드 조회 중...');
    return getCortar(region.lat, region.lon).then(function (cortar) {
      if (!cortar) {
        return apiPost('/api/agent/log', { job_id: jobId, msg: "  ✗ '" + region.name + "' 지역 코드 조회 실패", tag: 'error' })
          .then(function () { return apiPost('/api/agent/region_done', { job_id: jobId }); });
      }
      var isDong = /[동읍면리]$/.test(region.name.trim());
      var cortarNo = isDong ? (cortar.sectorNo || cortar.cortarNo) : (cortar.divisionNo || cortar.cortarNo);
      var maxCount = region.max_count || 500;

      setStatus('[' + region.index + '/' + region.total + '] ' + region.name + ' — 매물 목록 조회 중...');
      return getArticleList(cortarNo, maxCount, function (n) {
        setStatus('[' + region.index + '/' + region.total + '] ' + region.name + ' — 목록 ' + n + '건 확보');
      }).then(function (articleList) {
        return apiPost('/api/agent/log', { job_id: jobId, msg: '  목록 ' + articleList.length + '건 확보, 상세 조회 시작' })
          .then(function () {
            var BATCH = 6;
            var i = 0;
            function step() {
              if (i >= articleList.length) return Promise.resolve();
              var batch = articleList.slice(i, i + BATCH);
              setStatus('[' + region.index + '/' + region.total + '] ' + region.name +
                ' — 상세 조회 ' + (i + 1) + '~' + Math.min(i + BATCH, articleList.length) + '/' + articleList.length);
              return processBatch(batch).then(function (valid) {
                i += BATCH;
                var report = valid.length ? apiPost('/api/agent/report', { job_id: jobId, articles: valid }) : Promise.resolve();
                return report.then(function () { return sleep(150); }).then(step);
              });
            }
            return step();
          })
          .then(function () { return apiPost('/api/agent/region_done', { job_id: jobId }); });
      });
    });
  }

  function runJob(jobId) {
    function loop() {
      return apiGet('/api/agent/poll?job_id=' + jobId).then(function (region) {
        if (region.done) return;
        return processRegion(jobId, region).then(loop);
      });
    }
    return loop();
  }

  function mainLoop() {
    setStatus('작업 대기 중 — 웹/앱에서 "수집 시작"을 누르면 자동으로 시작됩니다');
    function check() {
      return apiGet('/api/agent/current_job?session_id=' + SESSION_ID).then(function (r) {
        if (r.job_id) {
          return runJob(r.job_id).then(function () {
            setStatus('완료! 다음 작업을 기다리는 중...');
          }).catch(function (e) {
            setStatus('오류: ' + e.message + ' — 다음 작업을 기다리는 중...');
          });
        }
      }).then(function () { return sleep(3000); }).then(check);
    }
    return check();
  }

  waitForJWT()
    .then(function () {
      setStatus('인증 완료');
      return mainLoop();
    })
    .catch(function (e) {
      setStatus('오류: ' + e.message);
      window.__naverAgentActive = false;
    });
})();
