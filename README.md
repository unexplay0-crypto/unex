# UNEX Vision — Player IPTV (Android TV / TV Box / Celular)

## Estrutura
- `lib/` código Flutter
- `native/MainActivity.kt` código nativo (brilho, volume, detecção de TV) — copiado para o projeto Android pelo workflow
- `.github/workflows/build.yml` compila o APK e publica a Release

## Como compilar
1. Envie **todo** o conteúdo desta pasta para a raiz do repositório (branch `main`).
2. Vá em **Actions → Gerar APK Android**; o APK aparece em *Artifacts* e em *Releases*.

## Atualização remota (OTA) — configurar 1 vez
O APK novo só instala por cima do antigo se for assinado com a **mesma chave**. Gere uma keystore fixa:

```bash
keytool -genkey -v -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
base64 -w0 debug.keystore      # copie a saída
```
No GitHub: **Settings → Secrets and variables → Actions → New secret** →
nome `DEBUG_KEYSTORE_BASE64`, valor = saída do base64. Guarde o arquivo `debug.keystore`.

A cada build o workflow publica `version.json` na Release; o app consulta
`https://github.com/<usuario>/<repo>/releases/latest/download/version.json` ao abrir.
Para forçar atualização, edite `"force": true` no `version.json` da Release.

## Dados salvos no aparelho
Catálogo processado, favoritos, histórico, progresso e último canal ficam no armazenamento
interno do app, com gravação atômica e cópia `.bak`.
