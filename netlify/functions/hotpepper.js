/* ============================================================
   ホットペッパー グルメ サーチAPI プロキシ
   ブラウザから直接APIキーを使うとCORSで弾かれる & キーが露出するため、
   Netlify Functions を経由してサーバー側でのみ呼び出す。
   対象エリアは設計シート3.5（兵庫県神戸市・三宮）に従い、
   件数が少ない場合は近隣の大きな地名・駅名にフォールバックする。
   ============================================================ */
const HOTPEPPER_ENDPOINT = "https://webservice.recruit.co.jp/hotpepper/gourmet/v1/";
const KEYWORD_FALLBACKS = ["三宮", "三ノ宮駅", "神戸市中央区", "神戸"];
const MIN_RESULTS = 5;
const MAX_COUNT = 100;

exports.handler = async function () {
  const apiKey = process.env.HOTPEPPER_API_KEY;
  if (!apiKey) {
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ error: "HOTPEPPER_API_KEY が設定されていません" }),
    };
  }

  let picked = null;
  let lastError = null;

  for (const keyword of KEYWORD_FALLBACKS) {
    const url = new URL(HOTPEPPER_ENDPOINT);
    url.searchParams.set("key", apiKey);
    url.searchParams.set("keyword", keyword);
    url.searchParams.set("count", String(MAX_COUNT));
    url.searchParams.set("format", "json");

    let data;
    try {
      const res = await fetch(url.toString());
      data = await res.json();
    } catch (e) {
      lastError = String(e);
      continue;
    }

    if (data && data.results && data.results.error) {
      lastError = JSON.stringify(data.results.error);
      continue;
    }

    const results = (data && data.results) || {};
    const shops = results.shop || [];
    const available = Number(results.results_available || shops.length);

    if (!picked || available > picked.available) {
      picked = { keyword, shops, available };
    }
    if (available >= MIN_RESULTS) break;
  }

  if (!picked) {
    return {
      statusCode: 502,
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ error: lastError || "ホットペッパーAPIから結果を取得できませんでした" }),
    };
  }

  const shops = picked.shops.map((s) => ({
    id: s.id,
    name: s.name,
    genre: s.genre && s.genre.name,
    budget: s.budget && s.budget.name,
    catch: s.catch,
    open: s.open,
    access: s.access,
    tel: s.tel,
    address: s.address,
    url: s.urls && s.urls.pc,
    photo: s.photo && s.photo.pc && (s.photo.pc.l || s.photo.pc.m || s.photo.pc.s),
    privateRoom: s.private_room,
    nonSmoking: s.non_smoking,
    lunch: s.lunch,
    card: s.card,
    parking: s.parking,
    wifi: s.wifi,
    midnight: s.midnight,
  }));

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
    body: JSON.stringify({
      keyword: picked.keyword,
      count: shops.length,
      available: picked.available,
      shops,
    }),
  };
};
