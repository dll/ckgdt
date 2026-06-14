'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "23a115ed28b6bab76ea90e4503ba7cac",
"assets/AssetManifest.bin.json": "3d62ca7c880b89b9d6ccf2b22c11e896",
"assets/AssetManifest.json": "fe630a2dd326f1e649675c07bb2a5605",
"assets/assets/achievement_templates/mobile_achievement_report_template.docx": "a058fca78ed23920527c1c4870c2b56b",
"assets/assets/achievement_templates/mobile_achievement_template_48.xlsx": "68451cbbd4eb3565af66c63d15f3a13b",
"assets/assets/agent_prompts/achievement.md": "a6e42298ca13a85cb12199eb53a3f148",
"assets/assets/agent_prompts/archive.md": "e5054c4c8887db3ef3a1cd9de5dcba11",
"assets/assets/agent_prompts/assessment.md": "468d153584c619545cae3eb998634e69",
"assets/assets/agent_prompts/assessment_grading.md": "32435c678caf9e0f82ad037e9b1940b7",
"assets/assets/agent_prompts/assistant.md": "bca584db240631e143935a41f5ac4d72",
"assets/assets/agent_prompts/courseware.md": "66c4fc7cfed715fa0688caa4dc6edd78",
"assets/assets/agent_prompts/course_gen.md": "b63797c9280968e44048bbd6e1db3cf4",
"assets/assets/agent_prompts/doc_converter.md": "e916c1f2290a357db7fb0a40f84e7c3c",
"assets/assets/agent_prompts/ethics.md": "95540d4238e28c302f2a2c91466aed18",
"assets/assets/agent_prompts/graph.md": "17f28af90ce82fee1505f4042487f928",
"assets/assets/agent_prompts/lab.md": "3ea40067cd64967aa828f3c6e8f7239f",
"assets/assets/agent_prompts/lab_grading.md": "6740ae07b647d4af38658c684c6b5a81",
"assets/assets/agent_prompts/learning.md": "73b6a28294d9c8ea0c6c5d561bea3c91",
"assets/assets/agent_prompts/madkg.md": "26ef4e68e97fecb0fbf92578fd2993dc",
"assets/assets/agent_prompts/mobile_expert.md": "1cd113fd6943260a7946471b2a4427db",
"assets/assets/agent_prompts/path.md": "d354dbbf07f0d253aab96ff613ccbee2",
"assets/assets/agent_prompts/quiz.md": "2d3bcbdf4b5b903445f379360f125d8c",
"assets/assets/agent_prompts/README.md": "68fd2d1c727140dd8c6b228a6e493d9c",
"assets/assets/agent_prompts/repo.md": "4c833565a1595767f160b5b104ac9798",
"assets/assets/agent_prompts/safety.md": "75fd932dea0e8ec670cbc9b0dcbae016",
"assets/assets/agent_prompts/tutor.md": "ee23aeb39008e9d97e4a64fe6dbba5c2",
"assets/assets/agent_prompts/virtual_student.md": "466a237bc4a71a183be9accff86b02c5",
"assets/assets/agent_prompts/virtual_teacher.md": "a475f06d8d13b4d5854d25876768cc72",
"assets/assets/agent_prompts/voice.md": "a81bf8990fc14c515a03dae61fa87566",
"assets/assets/agent_prompts/works.md": "985955e644680f20a02eb271c5443701",
"assets/assets/agent_prompts/works_grading.md": "856b8a3ab4ba4a25966da13994720517",
"assets/assets/archive_templates/beginning/obe_report.md": "1f7e699f2aade515ae8d5618876a848b",
"assets/assets/archive_templates/beginning/syllabus.md": "0ef246e09eea3c525fa27db7c3f60ea1",
"assets/assets/archive_templates/beginning/syllabus_evaluation.md": "7150e1eb6024afff47abc94143f262a1",
"assets/assets/archive_templates/beginning/syllabus_review.md": "bf8c7e3e13408c617e3b1b12d36fafc2",
"assets/assets/archive_templates/beginning/_index.md": "d0d9ac88f1a6eb7c158bb926c8963b5b",
"assets/assets/archive_templates/beginning/_ref/assessment_plan/%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B%25E7%25BB%25BC%25E5%2590%2588%25E8%2580%2583%25E6%25A0%25B8%25E6%2596%25B9%25E6%25A1%2588.md": "9eda60589e107d59905450b8b3ff1b83",
"assets/assets/archive_templates/beginning/_ref/student_guide/%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B%25E5%25AD%25A6%25E7%2594%259F%25E5%25AD%25A6%25E4%25B9%25A0%25E6%258C%2587%25E5%25AF%25BC%25E6%2589%258B%25E5%2586%258C.md": "80b268c56e696980db7968ee8dad6ba6",
"assets/assets/archive_templates/beginning/_ref/syllabus/%25E8%25AE%25A1%25E7%25A7%2591+6+%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B+%25E6%2595%2599%25E5%25AD%25A6%25E5%25A4%25A7%25E7%25BA%25B2+%25E5%2588%2598%25E4%25B8%259C%25E8%2589%25AF20251015.md": "3494f194fbd6ac3bae947856cfa396f6",
"assets/assets/archive_templates/beginning/_ref/teacher_guide/%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B%25E6%2595%2599%25E5%25B8%2588%25E6%2595%2599%25E5%25AD%25A6%25E6%258C%2587%25E5%25AF%25BC%25E6%2589%258B%25E5%2586%258C.md": "47ed041b8c2c2b6575eb42955fd71707",
"assets/assets/archive_templates/beginning/_ref/teaching_schedule/%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%2520-%2520%25E6%2595%2599%25E5%25AD%25A6%25E8%25BF%259B%25E5%25BA%25A6%25E8%25A1%25A8.md": "b32d1333952aa7c2859dd02551b21784",
"assets/assets/fonts/msyh.ttc": "fa04b86eb9c632ef04217c3e43d81c4d",
"assets/assets/fonts/msyhbd.ttc": "1166987f27a241b99b76f2d171eb84a6",
"assets/assets/fonts/simhei.ttf": "4093871a7f48e43b9ce7c38da0c34809",
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
"assets/assets/help/achievement_help.md": "b88865705e4cddfcecde88e5120e04d0",
"assets/assets/learning_data.db": "c45433798eadef01be4bd06e9b84baff",
"assets/assets/project_features.json": "72b8cde05987c17d67602356bc9bbb1a",
"assets/assets/students.json": "fce35bed0112a837b9d293b30add1670",
"assets/assets/student_group_data.json": "760c597971bc1a1824152086f8423ff6",
"assets/assets/student_repo_map.json": "ef08379c2d154e79550ac94c66eb51ee",
"assets/assets/syllabus/%25E8%25BD%25AF%25E4%25BB%25B6+6+%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B+%25E6%2595%2599%25E5%25AD%25A6%25E5%25A4%25A7%25E7%25BA%25B2+%25E5%2588%2598%25E4%25B8%259C%25E8%2589%25AF+new.md": "93c64be4bb6851c6ecebacee4d7bde88",
"assets/data/%25E7%2594%25A8%25E6%2588%25B7/%25E7%25AE%25A1%25E7%2590%2586%25E5%2591%2598%25E6%2595%2599%25E5%25B8%2588%25E5%2590%258D%25E5%258D%2595.xlsx": "bd34a70fe309a074cd45a67ecab629d0",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B%25E8%2580%2583%25E6%25A0%25B8%25E8%25AF%25B4%25E6%2598%258E.md": "5f1115a62720c0f8e5d59a55fdec20fe",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E6%258A%2580%25E6%259C%25AF%25E6%25A0%2588%25E5%25AE%258C%25E6%2595%25B4%25E6%2580%25A7%25E6%259B%25B4%25E6%2596%25B0%25E8%25AF%25B4%25E6%2598%258E.md": "4c84fa5ec3c6d4faec5764cc4d7742be",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E6%259B%25B4%25E6%2596%25B0%25E8%25AE%25A1%25E5%2588%2592.md": "220365f1838054d5357f6734f39110b7",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E7%25BB%25BC%25E5%2590%2588%25E8%2580%2583%25E6%25A0%25B8%25E6%2596%25B9%25E6%25A1%2588%25EF%25BC%2588%25E6%2595%25B4%25E5%2590%2588%25E7%2589%2588%25EF%25BC%2589.md": "5c3be0192feba710f73d9e6bb8c4e685",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E7%25BB%25BC%25E5%2590%2588%25E8%2580%2583%25E6%25A0%25B8%25E6%2596%25B9%25E6%25A1%2588+new.md": "76a472da5b682ea04b400e0b414031a3",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E7%25BB%25BC%25E5%2590%2588%25E8%2580%2583%25E6%25A0%25B8%25E6%2596%25B9%25E6%25A1%2588.md": "cf2f7ec3eccc73b5498c14479d16b4a4",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25AC%25AC%25E4%25B8%2580%25E5%2591%25A8%25E6%258A%25A5%25E5%2591%258A-%25E9%25A1%25B9%25E7%259B%25AE%25E5%2590%25AF%25E5%258A%25A8.md": "df304ed2a34c64a94b77db8580aa13af",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25AC%25AC%25E4%25B8%2589%25E5%2591%25A8%25E6%258A%25A5%25E5%2591%258A-%25E7%25B3%25BB%25E7%25BB%259F%25E6%2595%25B4%25E5%2590%2588.md": "7776c31a254a8991ec2b1777545c16fc",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25AC%25AC%25E4%25BA%258C%25E5%2591%25A8%25E6%258A%25A5%25E5%2591%258A-%25E6%25A0%25B8%25E5%25BF%2583%25E5%25BC%2580%25E5%258F%2591.md": "f1234e7f9ad368fe5b73f696a8487fd4",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E7%25AC%25AC%25E5%259B%259B%25E5%2591%25A8%25E6%258A%25A5%25E5%2591%258A-%25E6%25B5%258B%25E8%25AF%2595%25E4%25BA%25A4%25E4%25BB%2598.md": "980aa12e159d707c397c09efda4c352e",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%2580%2583%25E6%25A0%25B8%25E6%258A%25A5%25E5%2591%258A%25E4%25BD%2593%25E7%25B3%25BB%25E8%25AF%25B4%25E6%2598%258E.md": "ff618fcad014d6c19747ad07b74ee96e",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%2580%2583%25E6%25A0%25B8%25E6%258A%25A5%25E5%2591%258A1-%25E7%25AD%2594%25E8%25BE%25A9%25E6%258A%25A5%25E5%2591%258A.md": "23ca1068902872786a45980bec5b5d52",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%2580%2583%25E6%25A0%25B8%25E6%258A%25A5%25E5%2591%258A2-%25E4%25B8%25AA%25E4%25BA%25BA%25E6%258A%25A5%25E5%2591%258A.md": "683e58fa9202444f20ddd7b64f8c7cad",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%2580%2583%25E6%25A0%25B8%25E6%258A%25A5%25E5%2591%258A3-%25E5%25B0%258F%25E7%25BB%2584%25E6%258A%25A5%25E5%2591%258A.md": "6051ae957b525eda98c0e538d925480d",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%2580%2583%25E6%25A0%25B8%25E6%258A%25A5%25E5%2591%258A4-%25E9%25A1%25B9%25E7%259B%25AE%25E6%258A%25A5%25E5%2591%258A.md": "321d0e21bddb1c33f392875f1488f8fe",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/%25E8%25AF%25BE%25E7%25A8%258B%25E8%2580%2583%25E6%25A0%25B8%25E5%25A4%25A7%25E4%25BD%259C%25E4%25B8%259A.md": "22123d9188a30c148f26385bbfa3a782",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/2022210384+%25E5%25AD%2599%25E5%2598%2589%25E5%25A9%25A7+%25E8%25AF%25BE%25E7%25A8%258B%25E8%2580%2583%25E6%25A0%25B8%25E5%25A4%25A7%25E4%25BD%259C%25E4%25B8%259A.docx": "818fce95f07dc807fa1f947108b19677",
"assets/data/%25E8%2580%2583%25E6%25A0%25B8/README.md": "a53d00705a87c472537cdf1de23f6558",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "8fa502d4ec5aba78a9073a8e9f9e82f3",
"assets/NOTICES": "16c9b542a88c3881edb38308b641244b",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/media_kit/assets/web/hls1.4.10.js": "bd60e2701c42b6bf2c339dcf5d495865",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "8a5f575ecdf23f21bcae8204882d54bb",
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
"flutter_bootstrap.js": "ae285911164f77b0e27d9fac7d2b5e3a",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "85c3f39d339e60f7735290274290b72f",
"/": "85c3f39d339e60f7735290274290b72f",
"main.dart.js": "8eb2e2c7721c3364e1414b0a3cc9d928",
"manifest.json": "1689fa0c363894978d9ffcac145fdef5",
"sqflite_sw.js": "aac413f2e0c3b07b416d0ee8e4aa0c36",
"sqlite3.wasm": "fa7637a49a0e434f2a98f9981856d118",
"version.json": "2dce2408aa74fad9b8184d36a442cd47"};
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
