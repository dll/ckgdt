'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "61b9f35b9845457606255bb0e5fffb5c",
"assets/AssetManifest.bin.json": "0f884e3e67ca5822f58f69d19c177158",
"assets/AssetManifest.json": "de76007a96a9ac727c11c04ad4f2fbf5",
"assets/assets/achievement_templates/mobile_achievement_report_template.docx": "a058fca78ed23920527c1c4870c2b56b",
"assets/assets/achievement_templates/mobile_achievement_template_48.xlsx": "68451cbbd4eb3565af66c63d15f3a13b",
"assets/assets/agent_prompts/achievement.md": "0ba0a11f8853fc14f5fb76f7c45674f1",
"assets/assets/agent_prompts/archive.md": "a2ee04a7a779192d325d0bc8b78a60cd",
"assets/assets/agent_prompts/assessment.md": "f3524ac69e99fa3f05f4acc81472ea1b",
"assets/assets/agent_prompts/assessment_grading.md": "17d11765aa61b2fc44cb821c48a579cb",
"assets/assets/agent_prompts/assistant.md": "71356b0fe03106cd8ed5149cd36ff7c6",
"assets/assets/agent_prompts/case_demo.md": "954f64c34169ef8b41cf1541fd268f27",
"assets/assets/agent_prompts/courseware.md": "b1fd745a6f514d7a2e3235886a1d3429",
"assets/assets/agent_prompts/course_gen.md": "996e2c38d3528f379b070cd9dc9e4638",
"assets/assets/agent_prompts/digital_twin.md": "e274e4fde13124bc49cb830bd021ba53",
"assets/assets/agent_prompts/doc_converter.md": "25dd57879a022a56205ddcf0d372babc",
"assets/assets/agent_prompts/ethics.md": "2444d9f6ee907a22d11872735a6751ba",
"assets/assets/agent_prompts/grading.md": "75e2c6d0cef23cf388577cea2328350a",
"assets/assets/agent_prompts/graph.md": "63cc20ca7a0756da738e360f712923a1",
"assets/assets/agent_prompts/lab.md": "7c8f6e459d844e354b07b51105b1afa0",
"assets/assets/agent_prompts/lab_grading.md": "e62f8e53ba898e9e3a74868a6b271c4e",
"assets/assets/agent_prompts/learning.md": "8425c25421129204b854df8b41e313de",
"assets/assets/agent_prompts/madkg.md": "6afc643b8b61865b290339bea90a1fce",
"assets/assets/agent_prompts/mobile_expert.md": "a65e366e6387239e65ed83801bdaf382",
"assets/assets/agent_prompts/path.md": "ca780d9c1b6ba7a0dbf0e82c222fb8da",
"assets/assets/agent_prompts/quiz.md": "0bc48cba7273ed11c5880b67f970c3ce",
"assets/assets/agent_prompts/README.md": "207191562d3cabad486826280f39f6d1",
"assets/assets/agent_prompts/repo.md": "f31eb781989c32112eea13627f20a34b",
"assets/assets/agent_prompts/safety.md": "74bffc41034c3b284ecade998461fa3c",
"assets/assets/agent_prompts/tutor.md": "028cabd20921d5e295bdcfde2afdc9fd",
"assets/assets/agent_prompts/virtual_student.md": "b19e4224963c7b7949e362f227751625",
"assets/assets/agent_prompts/virtual_teacher.md": "403ee8aee7e6b37d9e93e2b8bcdf27f4",
"assets/assets/agent_prompts/voice.md": "ccbdde7600c0483e14d9b19232ab9c7f",
"assets/assets/agent_prompts/works.md": "622185530f7955873334f8e454f74dc5",
"assets/assets/agent_prompts/works_grading.md": "c4a39cf47ba75d0e3973bf5af565e09b",
"assets/assets/ai_key.txt": "2777eebc2c83f4132a3923a14c2f2356",
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
"assets/assets/graphs/ckgdt/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E9%2597%25AE%25E9%25A2%2598%25E5%259B%25BE%25E8%25B0%25B1.md": "fa996a35e3f9289827a0ba983437f5f3",
"assets/assets/graphs/ckgdt/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E7%259F%25A5%25E8%25AF%2586%25E4%25BD%2593%25E7%25B3%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "e8639f4e4dea751b60df4d23e4364a79",
"assets/assets/graphs/ckgdt/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2583%25BD%25E5%258A%259B%25E5%259F%25B9%25E5%2585%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "6ca8494dae3214c7ccc5b27ff5ab6c50",
"assets/assets/graphs/ckgdt/01-%25E8%25AF%25BE%25E7%25A8%258B%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E7%25A8%258B%25E7%259B%25AE%25E6%25A0%2587%25E5%259B%25BE%25E8%25B0%25B1.md": "c19d93d418d4efd71246996d7b590ea6",
"assets/assets/graphs/ckgdt/02-%25E6%258A%2580%25E6%259C%25AF%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25A4%259A%25E6%2599%25BA%25E8%2583%25BD%25E4%25BD%2593%25E7%25B3%25BB%25E7%25BB%259F.md": "d60bcc4fb67b86e286b2456b3fecade3",
"assets/assets/graphs/ckgdt/02-%25E6%258A%2580%25E6%259C%25AF%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2588%2586%25E6%259E%2590%25E6%258A%2580%25E6%259C%25AF.md": "d6b71257f3e8c03ca45acf579612d3b9",
"assets/assets/graphs/ckgdt/02-%25E6%258A%2580%25E6%259C%25AF%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%25B0%25E5%25AD%2597%25E5%25AD%25AA%25E7%2594%259F%25E6%258A%2580%25E6%259C%25AF.md": "d016d4a3caa68f8f02ba8206049b415a",
"assets/assets/graphs/ckgdt/02-%25E6%258A%2580%25E6%259C%25AF%25E5%259B%25BE%25E8%25B0%25B1/%25E7%259F%25A5%25E8%25AF%2586%25E5%259B%25BE%25E8%25B0%25B1%25E6%258A%2580%25E6%259C%25AF.md": "d66b516f19659a507f515b1dd55f2b2b",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2580%2520%25E5%25B9%25B3%25E5%258F%25B0%25E5%259F%25BA%25E7%25A1%2580%25E6%2593%258D%25E4%25BD%259C.md": "f926d65cae534621036f00d267a232ef",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2583%2520%25E6%2595%2599%25E5%25B8%2588%25E7%25AB%25AF%25E6%2595%2599%25E5%25AD%25A6%25E7%25AE%25A1%25E7%2590%2586.md": "4d4a802d1edef59b4a4fd98d16b27a2a",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25B8%2589%2520%25E6%2595%25B0%25E5%25AD%2597%25E5%25AD%25AA%25E7%2594%259F%25E5%259C%25BA%25E6%2599%25AF%25E8%25AE%25BE%25E8%25AE%25A1.md": "8b3343f734f0c22fd41b2b0152cc0961",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%258C%2520%25E7%259F%25A5%25E8%25AF%2586%25E5%259B%25BE%25E8%25B0%25B1%25E5%25BB%25BA%25E6%25A8%25A1.md": "e5696459de2b9545764cdfc54c6193db",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E4%25BA%2594%2520%25E5%25AE%259E%25E9%25AA%258C%25E7%25AE%25A1%25E7%2590%2586%25E4%25B8%258EAI%25E6%2589%25B9%25E9%2598%2585.md": "7d8fc11917a136434ab65167c39285d0",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%2585%25AB%2520%25E5%25AD%25A6%25E7%2594%259F%25E7%25AB%25AF%25E8%2587%25AA%25E4%25B8%25BB%25E5%25AD%25A6%25E4%25B9%25A0.md": "61aa3a1ffc3956e53565aea99ee26c97",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%2585%25AD%2520%25E7%25BB%25BC%25E5%2590%2588%25E9%25A1%25B9%25E7%259B%25AE.md": "d655d37e457457eace0ac503f3edab53",
"assets/assets/graphs/ckgdt/03-%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%259B%259B%2520%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2588%2586%25E6%259E%2590%25E4%25BB%25AA%25E8%25A1%25A8%25E7%259B%2598.md": "561a9159cbee45d15ed145959b3e94ce",
"assets/assets/graphs/ckgdt/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2588%2586%25E6%259E%2590%25E5%25AE%259E%25E8%25B7%25B5%25E9%25A1%25B9%25E7%259B%25AE.md": "0a74d0f0a097c88b031a1e683f8dc45d",
"assets/assets/graphs/ckgdt/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%25B0%25E5%25AD%2597%25E5%25AD%25AA%25E7%2594%259F%25E6%2595%2599%25E5%25AD%25A6%25E8%25AE%25BE%25E8%25AE%25A1%25E9%25A1%25B9%25E7%259B%25AE.md": "b0430ff918bc5576875ce6c8bba3109f",
"assets/assets/graphs/ckgdt/04-%25E9%25A1%25B9%25E7%259B%25AE%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E7%25A8%258B%25E7%259F%25A5%25E8%25AF%2586%25E5%259B%25BE%25E8%25B0%25B1%25E6%259E%2584%25E5%25BB%25BA%25E9%25A1%25B9%25E7%259B%25AE.md": "04d57945fae3107c5bbbd6aefb6b4108",
"assets/assets/graphs/ckgdt/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E5%2586%2585%25E5%25AE%25B9%25E4%25BD%2593%25E7%25B3%25BB%25E5%259B%25BE%25E8%25B0%25B1.md": "0d6516e99045fa725fcfc370a42711ee",
"assets/assets/graphs/ckgdt/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E6%2596%25B9%25E6%25B3%2595%25E7%25AD%2596%25E7%2595%25A5%25E5%259B%25BE%25E8%25B0%25B1.md": "0ccc15a0fc3ad50ff04f337ff30e250f",
"assets/assets/graphs/ckgdt/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E6%2595%2599%25E5%25AD%25A6%25E8%25B5%2584%25E6%25BA%2590%25E9%2585%258D%25E7%25BD%25AE%25E5%259B%25BE%25E8%25B0%25B1.md": "beb6736cf1fce4b72a3fc2b491180b6a",
"assets/assets/graphs/ckgdt/05-%25E6%2595%2599%25E5%25AD%25A6%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2580%2583%25E6%25A0%25B8%25E5%25AE%259E%25E6%2596%25BD%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "719dc391387e77f14f2808843af5cd9b",
"assets/assets/graphs/ckgdt/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2586%2585%25E5%25AE%25B9%25E5%25AF%25BC%25E8%2588%25AA%25E5%259B%25BE%25E8%25B0%25B1.md": "e2c61c72100ccfc859458010b33a9125",
"assets/assets/graphs/ckgdt/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AD%25A6%25E4%25B9%25A0%25E6%2596%25B9%25E6%25B3%2595%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "6bc571e298a14b0761d3995dc172cd27",
"assets/assets/graphs/ckgdt/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E5%25AD%25A6%25E4%25B9%25A0%25E6%258C%2587%25E5%25AF%25BC%25E5%259B%25BE%25E8%25B0%25B1.md": "3b8bf4fc8f2c1e734a12a05d46b0070f",
"assets/assets/graphs/ckgdt/06-%25E5%25AD%25A6%25E4%25B9%25A0%25E5%259B%25BE%25E8%25B0%25B1/%25E8%2580%2583%25E6%25A0%25B8%25E5%25BA%2594%25E5%25AF%25B9%25E7%25AD%2596%25E7%2595%25A5%25E5%259B%25BE%25E8%25B0%25B1.md": "78abad2e5eb3604130439cc79579739f",
"assets/assets/graphs/ckgdt/07-%25E6%2580%259D%25E6%2594%25BF%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E7%25A8%258B%25E6%2580%259D%25E6%2594%25BF%25E5%259B%25BE%25E8%25B0%25B1.md": "6a7607c52179417b925924317c1ab31c",
"assets/assets/graphs/ckgdt/08-%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1/%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1%25E6%2580%25BB%25E8%25A7%2588.md": "10532878b56ed1194f6c5fca192031aa",
"assets/assets/graphs/ckgdt/08-%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC1%25E7%25AB%25A0%2520%25E8%25AF%25BE%25E7%25A8%258B%25E7%259F%25A5%25E8%25AF%2586%25E5%259B%25BE%25E8%25B0%25B1%25E5%259F%25BA%25E7%25A1%2580-%25E4%25BD%259C%25E4%25B8%259A%25E8%25AF%25A6%25E8%25A7%25A3.md": "6f2f058ed2ee26f3fb9ff49bc16027ff",
"assets/assets/graphs/ckgdt/08-%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC2%25E7%25AB%25A0%2520%25E8%25AF%25BE%25E7%25A8%258B%25E6%2595%25B0%25E6%258D%25AE%25E5%25BB%25BA%25E6%25A8%25A1%25E4%25B8%258E%25E8%25B5%2584%25E6%25BA%2590%25E6%25B2%25BB%25E7%2590%2586-%25E4%25BD%259C%25E4%25B8%259A%25E8%25AF%25A6%25E8%25A7%25A3.md": "8fe1ef2bfc9350ec9a1f702e57076996",
"assets/assets/graphs/ckgdt/08-%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC3%25E7%25AB%25A0%2520%25E6%2595%25B0%25E5%25AD%2597%25E5%25AD%25AA%25E7%2594%259F%25E6%2595%2599%25E5%25AD%25A6%25E5%259C%25BA%25E6%2599%25AF%25E8%25AE%25BE%25E8%25AE%25A1-%25E4%25BD%259C%25E4%25B8%259A%25E8%25AF%25A6%25E8%25A7%25A3.md": "6e27c5013ad0850bf77ab7e7c50e233f",
"assets/assets/graphs/ckgdt/08-%25E4%25BD%259C%25E4%25B8%259A%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC4%25E7%25AB%25A0%2520%25E6%2599%25BA%25E8%2583%25BD%25E5%25AD%25A6%25E4%25B9%25A0%25E8%25B7%25AF%25E5%25BE%2584%25E4%25B8%258E%25E5%25AD%25A6%25E4%25B9%25A0%25E5%2588%2586%25E6%259E%2590-%25E4%25BD%259C%25E4%25B8%259A%25E8%25AF%25A6%25E8%25A7%25A3.md": "87f7df6b79e9d4a5729e3cae2780563b",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E4%25B8%25AA%25E4%25BA%25BA%25E5%25AD%25A6%25E4%25B9%25A0%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "40994b92d32cebf75d674bb39d2fc928",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1%25E6%2580%25BB%25E8%25A7%2588.md": "9b69baf1046548e9e5dab09cff110c6a",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25AE%259E%25E9%25AA%258C%25E6%258A%25A5%25E5%2591%258A%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "cd121339b2de30055ea53ea0c5ca0f81",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E5%25B0%258F%25E7%25BB%2584%25E5%258D%258F%25E4%25BD%259C%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "cfa64dfe41334f9b24ecb8f91439d0b9",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25BB%25BC%25E5%2590%2588%25E9%25A1%25B9%25E7%259B%25AE%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "717df1873637d4b4098d1650fcf3bec3",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25A7%2586%25E9%25A2%2591%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "00f86c1d49227a3d410a129b30810f8b",
"assets/assets/graphs/ckgdt/09-%25E4%25BD%259C%25E5%2593%2581%25E5%259B%25BE%25E8%25B0%25B1/%25E8%25AF%25BE%25E4%25BB%25B6%25E4%25BD%259C%25E5%2593%2581%25E8%25AF%25A6%25E8%25A7%25A3.md": "b4f3870f2cf61132f6f985f1532c1b32",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC1%25E7%25AB%25A0-%25E8%2580%2583%25E6%25A0%25B8%25E6%2596%25B9%25E6%25A1%2588%25E4%25B8%258E%25E6%2588%2590%25E7%25BB%25A9%25E6%259E%2584%25E6%2588%2590.md": "f8afe69ef4d03688706298b8650a86c4",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC2%25E7%25AB%25A0-%25E5%25B9%25B3%25E6%2597%25B6%25E6%2588%2590%25E7%25BB%25A9%25E7%25BB%2586%25E5%2588%2599.md": "07356e48216e6c9799db497d5173a13b",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC3%25E7%25AB%25A0-%25E5%25AE%259E%25E9%25AA%258C%25E6%2588%2590%25E7%25BB%25A9%25E7%25BB%2586%25E5%2588%2599.md": "29a8d2929964271ae5d31417e4ba3bf7",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC4%25E7%25AB%25A0-%25E6%259C%259F%25E6%259C%25AB%25E8%2580%2583%25E6%259F%25A5%25E7%25BB%2586%25E5%2588%2599.md": "ff382a4e05e8dfa5996fa16801c13d8d",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC5%25E7%25AB%25A0-%25E6%258A%25A5%25E5%2591%258A%25E4%25BD%2593%25E7%25B3%25BB%25E4%25B8%258E%25E8%25AF%2584%25E5%2588%2586%25E6%25A0%2587%25E5%2587%2586.md": "0c943b45d20c2b8110f28eeac8241124",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/%25E7%25AC%25AC6%25E7%25AB%25A0-%25E8%25BE%25BE%25E6%2588%2590%25E5%25BA%25A6%25E8%25AF%2584%25E4%25BB%25B7%25E7%259F%25A9%25E9%2598%25B5.md": "fd221c262344b13830b7c97548d8e64a",
"assets/assets/graphs/ckgdt/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1/10-%25E8%2580%2583%25E6%25A0%25B8%25E5%259B%25BE%25E8%25B0%25B1.md": "8a53f4f2f04e49d0ceb3b2138429fa8d",
"assets/assets/help/achievement_help.md": "b88865705e4cddfcecde88e5120e04d0",
"assets/assets/learning_data.db": "0a925340d514a034cf331a8b4e71f7a6",
"assets/assets/project_features.json": "72b8cde05987c17d67602356bc9bbb1a",
"assets/assets/students.json": "085bf587af83f460a7fe9da6072d9b89",
"assets/assets/student_group_data.json": "760c597971bc1a1824152086f8423ff6",
"assets/assets/student_repo_map.json": "ef08379c2d154e79550ac94c66eb51ee",
"assets/assets/syllabus/%25E8%25BD%25AF%25E4%25BB%25B6+6+%25E3%2580%258A%25E7%25A7%25BB%25E5%258A%25A8%25E5%25BA%2594%25E7%2594%25A8%25E5%25BC%2580%25E5%258F%2591%25E3%2580%258B+%25E6%2595%2599%25E5%25AD%25A6%25E5%25A4%25A7%25E7%25BA%25B2+%25E5%2588%2598%25E4%25B8%259C%25E8%2589%25AF+new.md": "93c64be4bb6851c6ecebacee4d7bde88",
"assets/data/old/%25E7%2594%25A8%25E6%2588%25B7/%25E7%25AE%25A1%25E7%2590%2586%25E5%2591%2598%25E6%2595%2599%25E5%25B8%2588%25E5%2590%258D%25E5%258D%2595.xlsx": "bd34a70fe309a074cd45a67ecab629d0",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/%25E8%25B5%2584%25E6%25BA%2590%25E7%25B4%25A2%25E5%25BC%2595.json": "49a0a48ee640af8590197d13601a0c84",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/assessment.json": "87872f734a351195353b5a9753a24e75",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/chapters.json": "32390fbca939efcf73a4279d3bd41bb5",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/course_profile.json": "511b8fcec3eba90b58641bde498e71e4",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/lab_tasks.json": "22a87eb3a49629f214991446817e46d3",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/manifest.json": "492c3b6126e2294051da4c5bbeb622ca",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/materials_manifest.json": "42df32dde2017100723b2e5e27034b0e",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/platform_readiness.json": "079bd4593c02d9bb008226f97d54240a",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/report_templates.json": "fe8de03ad7af5e8901536c601c9a0105",
"assets/data/old/%25E9%2585%258D%25E7%25BD%25AE/resource_repos.json": "ab01374b3c7549889462b1a7b2f7c7ac",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "ba83ead8ddd83092d734ae9177f91f3e",
"assets/NOTICES": "2cc0274bc88a3af9e8e5cd62a4fe4d93",
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
"flutter_bootstrap.js": "a1fade2e5a32f91dca9acb367096a0f6",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "b6e0e049a78e6b44d1647168f4ae5be6",
"/": "b6e0e049a78e6b44d1647168f4ae5be6",
"main.dart.js": "5cf2f2cb5b2d58de3eef44a68e877f7f",
"manifest.json": "ef9d3d212e6fa01621cfb85f1f3a1b17",
"sqflite_sw.js": "aac413f2e0c3b07b416d0ee8e4aa0c36",
"sqlite3.wasm": "fa7637a49a0e434f2a98f9981856d118",
"version.json": "a3cf32f787720fcc4798837b6cfc61d8"};
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
