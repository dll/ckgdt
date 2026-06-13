// 生成答辩PPTX: 整页slide PNG铺满 + 每页讲稿备注。
// 运行: node gen_pptx.js   读取 deck.json + slides/*.png
const pptxgen = require("pptxgenjs");
const fs = require("fs");
const path = require("path");

const deck = JSON.parse(fs.readFileSync(path.join(__dirname, "deck.json"), "utf-8"));
const pptx = new pptxgen();
pptx.defineLayout({ name: "FHD", width: 13.333, height: 7.5 });
pptx.layout = "FHD";
pptx.author = "刘畅";
pptx.title = deck.title;

deck.slides.forEach((s) => {
  const slide = pptx.addSlide();
  slide.background = { color: "0A1428" };
  slide.addImage({
    path: path.join(__dirname, s.png),
    x: 0, y: 0, w: 13.333, h: 7.5,
  });
  if (s.note) slide.addNotes(s.note);
});

const out = path.join(__dirname, "..", "面向异构飞行器协同作战的编队策略研究_答辩.pptx");
pptx.writeFile({ fileName: out }).then(() => {
  console.log("PPTX written ->", out);
});
