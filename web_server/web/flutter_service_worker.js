'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "5c70ddd2d686821a1f7f48125a4d0b2d",
"assets/AssetManifest.bin.json": "e6296ad56b41ae4afc3d4162f0ed895f",
"assets/AssetManifest.json": "b689804750401dee6006f050d0d56e22",
"assets/assets/fonts/msyh.ttc": "fa04b86eb9c632ef04217c3e43d81c4d",
"assets/assets/fonts/msyhbd.ttc": "1166987f27a241b99b76f2d171eb84a6",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E5%259B%25BE%25E8%25B0%25B1%25E4%25BC%2598%25E5%258C%2596%25E5%25AE%258C%25E6%2588%2590%25E6%2580%25BB%25E7%25BB%2593.md": "9c1fd7acf193774edfceb0ad87a72712",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E9%2597%25AE%25E9%25A2%2598%25E5%259B%25BE%25E8%25B0%25B1.md": "dc47c3345886715cfd522d7836ec69c7",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E7%259F%25A5%25E8%25AF%2586%25E4%25BD%2593%25E7%25B3%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "b16882b3fb79338c5f815665ddd8ff04",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2583%25BD%25E5%258A%259B%25E5%259F%25B9%25E5%2585%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "2c4c0c6cf56b7dd16b956248e799080b",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E7%25A8%258B%25E6%2580%259D%25E6%2594%25BF%25E5%259B%25BE%25E8%25B0%25B1.md": "e238c24aaf7640988991235754f2eba7",
"assets/assets/graphs/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E7%25A8%258B%25E7%259B%25AE%25E6%25A0%2587%25E5%259B%25BE%25E8%25B0%25B1.md": "8c610eff7e4347cd6e6f969c53e0675b",
"assets/assets/graphs/02-%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1/%25E5%258D%258E%25E4%25B8%25BA%25E5%25A4%259A%25E7%25AB%25AF%25E5%25BC%2580%25E5%258F%2591%25E5%259B%25BE%25E8%25B0%25B1.md": "7a9b8b226be4d59738bc09ba0bd68835",
"assets/assets/graphs/02-%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1/%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1%25E4%25BC%2598%25E5%258C%2596%25E5%25AE%258C%25E6%2588%2590%25E6%2580%25BB%25E7%25BB%2593.md": "b55894691ad021b95e6096e1a0fb4760",
"assets/assets/graphs/02-%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BC%2580%25E5%258F%2591%25E5%259B%25BE%25E8%25B0%25B1.md": "bb199b8553db0894c6ae8020d0d90fce",
"assets/assets/graphs/02-%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1/Android%25E5%258E%259F%25E7%2594%259F%25E5%25BC%2580%25E5%258F%2591%25E5%259B%25BE%25E8%25B0%25B1.md": "a6ba1450e534ba3310c6efcd8e3bc340",
"assets/assets/graphs/02-%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%259B%25BE%25E8%25B0%25B1/iOS%25E5%258E%259F%25E7%2594%259F%25E5%25BC%2580%25E5%258F%2591%25E5%259B%25BE%25E8%25B0%25B1.md": "fb5bad662f50d563182165a38c632c2e",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2580%2520%25E5%25BC%2580%25E5%258F%2591%25E7%258E%25AF%25E5%25A2%2583%25E6%2590%25AD%25E5%25BB%25BA.md": "e224b4447f809adbdfe1b133530d2db8",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2589%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591.md": "419be1a44f2a8d4aeb1f89e89a1e8dbe",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%258C%2520%25E5%258E%259F%25E7%2594%259F%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591.md": "79ecd59c6ec7b889c69837141beb8222",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%2594%2520%25E9%25B8%25BF%25E8%2592%2599%25E5%25A4%259A%25E7%25AB%25AF%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591.md": "1b3949179df9a9cf49f9dfd0170532c1",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%2585%25AD%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E7%25BB%25BC%25E5%2590%2588%25E9%25A1%25B9%25E7%259B%25AE%25E5%25AE%259E%25E6%2588%2598.md": "a4ca8715731089e09599f950a2b09b7c",
"assets/assets/graphs/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%259B%2520%25E5%25BE%25AE%25E4%25BF%25A1%25E5%25B0%258F%25E7%25A8%258B%25E5%25BA%258F%25E5%25BC%2580%25E5%258F%2591.md": "098a87c7c2d3ac10f5a2e5e804d95f0c",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1%25E4%25BC%2598%25E5%258C%2596%25E5%25AE%258C%25E6%2588%2590%25E6%2580%25BB%25E7%25BB%2593.md": "9afb9080a451d266443f1b436426c1bd",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE1-%25E4%25B8%25AA%25E4%25BA%25BA%25E8%25AE%25B0%25E8%25B4%25A6%25E5%25BA%2594%25E7%2594%25A8.md": "61efa20371e937203a51765a94d7fbd0",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE1-%25E6%2599%25BA%25E6%2585%25A7%25E6%25A0%25A1%25E5%259B%25AD%25E7%2594%259F%25E6%25B4%25BB%25E6%259C%258D%25E5%258A%25A1%25E5%25B9%25B3%25E5%258F%25B0.md": "34835bf0ee7134d10762001c5526eb22",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE2-%25E5%259C%25A8%25E7%25BA%25BF%25E5%25AD%25A6%25E4%25B9%25A0%25E5%25B9%25B3%25E5%258F%25B0.md": "4c08134ae847e31c8afdab79919d3543",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE2-%25E5%259C%25A8%25E7%25BA%25BF%25E5%25AD%25A6%25E4%25B9%25A0%25E8%25BE%2585%25E5%258A%25A9%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BC%2580%25E5%258F%2591%25E4%25B8%258E%25E6%2595%25B4%25E5%2590%2588.md": "b76ffb936269b06d22be7500b8eae83a",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE3-%25E6%2599%25BA%25E8%2583%25BD%25E5%2581%25A5%25E5%25BA%25B7%25E5%258A%25A9%25E6%2589%258B.md": "8a5cc2ac82eaad4e6d307d108ac77fe3",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE3-%25E6%2599%25BA%25E8%2583%25BD%25E5%2581%25A5%25E5%25BA%25B7%25E8%25BF%2590%25E5%258A%25A8%25E8%25AE%25B0%25E5%25BD%2595%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BC%2580%25E5%258F%2591%25E4%25B8%258E%25E6%2595%25B4%25E5%2590%2588.md": "441ec029f6b73b73b34477f434a158f4",
"assets/assets/graphs/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E9%25A1%25B9%25E7%259B%25AE4-%25E4%25BA%258C%25E6%2589%258B%25E7%2589%25A9%25E5%2593%2581%25E4%25BA%25A4%25E6%2598%2593%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BC%2580%25E5%258F%2591%25E4%25B8%258E%25E6%2595%25B4%25E5%2590%2588.md": "3942c204c7ff1304a6fa2012cb02b1ac",
"assets/assets/graphs/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E5%2586%2585%25E5%25AE%25B9%25E4%25BD%2593%25E7%25B3%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "ed790dcbbb584608d6aea9391f131c47",
"assets/assets/graphs/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E6%2596%25B9%25E6%25B3%2595%25E7%25AD%2596%25E7%2595%25A5%25E5%259B%25BE%25E8%25B0%25B1.md": "59d54b278fddd520a0106fca22a7f5d2",
"assets/assets/graphs/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E8%25B5%2584%25E6%25BA%2590%25E9%2585%258D%25E7%25BD%25AE%25E5%259B%25BE%25E8%25B0%25B1.md": "eb0c4400705d883bfd72778282310fce",
"assets/assets/graphs/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2580%2583%25E6%25A0%25B8%25E5%25AE%259E%25E6%2596%25BD%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "a4fabbb4484fbab99e53a0c8052637f3",
"assets/assets/graphs/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2586%2585%25E5%25AE%25B9%25E5%25AF%25BC%25E8%2588%25AA%25E5%259B%25BE%25E8%25B0%25B1.md": "a3811a841d73a2e1276f901419e643d9",
"assets/assets/graphs/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E6%2596%25B9%25E6%25B3%2595%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "04bc4cce8b61f6e6cedcb624868c9af8",
"assets/assets/graphs/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%25AD%25A6%25E4%25B9%25A0%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "a0b8c6df0c564f942213d2b9ff34f329",
"assets/assets/graphs/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2580%2583%25E6%25A0%25B8%25E5%25BA%2594%25E5%25AF%25B9%25E7%25AD%2596%25E7%2595%25A5%25E5%259B%25BE%25E8%25B0%25B1.md": "96b232b777701daf195afb0b361f25ae",
"assets/assets/learning_data.db": "1839b397ecdfe2c6278d3e25693b996f",
"assets/assets/project_features.json": "72b8cde05987c17d67602356bc9bbb1a",
"assets/assets/students.json": "fce35bed0112a837b9d293b30add1670",
"assets/assets/student_group_data.json": "760c597971bc1a1824152086f8423ff6",
"assets/assets/student_repo_map.json": "ef08379c2d154e79550ac94c66eb51ee",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC/%25E4%25BA%25A4%25E4%25BA%2592%25E9%25A1%25BA%25E5%25BA%258F%25E5%259B%25BE_StarUML.puml": "7133f2c2abe63c2e8b7a236dc4d3bd5a",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC/%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC%25E4%25B9%25A6_new.md": "491209b86350a20c72928eba8a8849de",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC/%25E7%25BB%2584%25E4%25BB%25B6%25E6%25A8%25A1%25E5%259E%258B%25E5%259B%25BE_StarUML.puml": "0ad6fa03afe81134fcefd209a0104235",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC/%25E9%2583%25A8%25E7%25BD%25B2%25E6%25A8%25A1%25E5%259E%258B%25E5%259B%25BE_StarUML.puml": "081b77b4f5029240c00c06dcbec605ce",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%258C%2587%25E5%25AF%25BC/MVVM%25E6%25A8%25A1%25E5%259E%258B%25E5%259B%25BE_StarUML.puml": "4f1ed0018782910013ec9d0a56d5c849",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2580%2520%25E5%25BC%2580%25E5%258F%2591%25E7%258E%25AF%25E5%25A2%2583%25E6%2590%25AD%25E5%25BB%25BA_new.md": "e57dda0caefdab8a8c5baf2408d97c94",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2589%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591_new.md": "7b85e0c63068d3ac671cf68d2c7b5c15",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%258C%2520%25E5%258E%259F%25E7%2594%259F%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591_new.md": "f84ccb057d29bd1c80573f5fa1312870",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%2594%2520%25E9%25B8%25BF%25E8%2592%2599%25E5%25A4%259A%25E7%25AB%25AF%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591_new.md": "f62fff49031b39c5f36ac39481651ce1",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E5%2585%25AD%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E7%25BB%25BC%25E5%2590%2588%25E9%25A1%25B9%25E7%259B%25AE%25E5%25AE%259E%25E6%2588%2598_new.md": "88c9f47382dc1992437b0ac4b59217f1",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E5%25AE%259E%25E9%25AA%258C%25E6%2595%2599%25E7%25A8%258B/%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%259B%2520%25E5%25BE%25AE%25E4%25BF%25A1%25E5%25B0%258F%25E7%25A8%258B%25E5%25BA%258F%25E5%25BC%2580%25E5%258F%2591_new.md": "9766fc771bf57e9a05c9a1e76c3bed33",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2580%2520%25E5%25BC%2580%25E5%258F%2591%25E7%258E%25AF%25E5%25A2%2583%25E6%2590%25AD%25E5%25BB%25BA%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "e0294ec0a5679a0658dcfe7ca3aea09a",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2589%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "9b8ae56db5a62323207635cdac54df4b",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%258C%2520%25E5%258E%259F%25E7%2594%259F%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "7798a2d0da5a36bebeb6fdcf95dd9e71",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%2594%2520%25E9%25B8%25BF%25E8%2592%2599%25E5%25A4%259A%25E7%25AB%25AF%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "be3b0ce0ee4ab6e52e49f0c39df7d9fe",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E5%2585%25AD%2520%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E7%25BB%25BC%25E5%2590%2588%25E9%25A1%25B9%25E7%259B%25AE%25E5%25AE%259E%25E6%2588%2598%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "2ef076f1df082a3146c2646d71cb7f79",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF/%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%259B%2520%25E5%25BE%25AE%25E4%25BF%25A1%25E5%25B0%258F%25E7%25A8%258B%25E5%25BA%258F%25E5%25BC%2580%25E5%258F%2591%25E6%258A%25A5%25E5%2591%258A%25E6%25A8%25A1%25E6%259D%25BF.md": "37ba5f31b9466aca1dda1431c135f2b0",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/%25E5%25B5%258C%25E5%2585%25A5%25E5%25BC%258FC-C++%25E5%25BC%2580%25E5%258F%2591%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "bb59421ec842c8b30b6763313dd7c586",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/ArkUI%25E5%25BC%2580%25E5%258F%2591%25E9%25B8%25BF%25E8%2592%2599%25E5%25A4%259A%25E7%25AB%25AF%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "f2ec5ac7313cf2615f518d2bb3ddcb07",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Cordova%25E5%25BC%2580%25E5%258F%2591%25E6%25B7%25B7%25E5%2590%2588%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "d1cea946deebd4e2f64e16f8787b5839",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Flutter%25E5%25BC%2580%25E5%258F%2591%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "891a65c8832e1b7ca4791d7f4eac953f",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Java%25E5%25BC%2580%25E5%258F%2591Android%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "49e46fe927e50067d7295c2c81655ba6",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Kotlin%25E5%25BC%2580%25E5%258F%2591Android%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "18558e1615e887c60fb00c817421fb67",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/MAUI%25E5%25BC%2580%25E5%258F%2591%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "43745b07f34dacb506cbc5f5a6767b6d",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Swift%25E5%25BC%2580%25E5%258F%2591iOS%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "fa3d5772b94d9957571059b693519e2d",
"assets/data/%25E5%25AE%259E%25E9%25AA%258C/%25E7%25A7%25BB%25E5%258A%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588/Uniapp%25E5%25BC%2580%25E5%258F%2591%25E8%25B7%25A8%25E5%25B9%25B3%25E5%258F%25B0%25E5%25BA%2594%25E7%2594%25A8%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E6%2589%258B%25E5%2586%258C.md": "1c3ed08ca2427570436e3437dc10a5ca",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "e5f0a44fa2f05560a82bfce3e13c22a2",
"assets/NOTICES": "46f4d27442f160685e5da37eb39f20f0",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "c37c1d56770b47996e95ae84d56aed75",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "b8c78906bc32f70c683835e8b3fc21b1",
"/": "b8c78906bc32f70c683835e8b3fc21b1",
"main.dart.js": "8b525c7de41d0ba9790c1e35e80349e1",
"manifest.json": "eaa5522fc2c5ac0bf8aae14eb12f8b43",
"sqflite_sw.js": "aac413f2e0c3b07b416d0ee8e4aa0c36",
"sqlite3.wasm": "fa7637a49a0e434f2a98f9981856d118",
"version.json": "e8c4f36c976d645a170b22c48c731bb1"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
