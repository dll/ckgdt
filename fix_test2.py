path = 'test/services/rich_resource_generation_service_test.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Add ensureInitialized at start of main
old_main = "void main() {\n  const aiConfig = AiConfigModel("
new_main = "void main() {\n  TestWidgetsFlutterBinding.ensureInitialized();\n\n  const aiConfig = AiConfigModel("
text = text.replace(old_main, new_main)

# Add createSessionDir override to fake courseware
old_fake = "  @override\n  Future<bool> isPythonPptxInstalled() async => true;"
new_fake = """  @override
  Future<String> createSessionDir() async => '/tmp/session';

  @override
  Future<bool> isPythonPptxInstalled() async => true;"""
text = text.replace(old_fake, new_fake)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print('test updated')
