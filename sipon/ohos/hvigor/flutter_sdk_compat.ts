import fs from 'fs';
import path from 'path';
import { createHash } from 'crypto';
import { execFileSync } from 'child_process';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

// Flutter OH 3.41.10 includes API 26 autofill declarations even when building
// with a public API 24 SDK. Its runtime guard already rejects API < 26. Keep
// the same fallback in a project-local copy so older SDKs can compile it.
export function flutterSdkCompat(projectPath: string): HvigorPlugin {
  return {
    pluginId: 'sipon-flutter-sdk-compat',
    apply(rootNode: HvigorNode) {
      rootNode.afterNodeEvaluate(() => {
        const sdkRoot = process.env.DEVECO_SDK_HOME;
        if (!sdkRoot) return;
        const declaration = path.join(sdkRoot, 'default', 'openharmony', 'ets', 'api',
          '@ohos.app.ability.autoFillManager.d.ts');
        if (!fs.existsSync(declaration)) return;
        if (/\bfunction\s+requestAutoFill\s*\(/.test(fs.readFileSync(declaration, 'utf8'))) return;
        const appContext = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
        const overrides = appContext.getOverrides() ?? {};
        const original = overrides['@ohos/flutter_ohos'];
        if (!original?.startsWith('file:')) return;
        const harPath = original.substring(5);
        const hash = createHash('sha256').update('sipon-api24-v1').update(fs.readFileSync(harPath))
          .digest('hex').substring(0, 16);
        const unpackDir = path.join(projectPath, 'build', 'flutter_sdk_compat', hash);
        const packageDir = path.join(unpackDir, 'package');
        const compatibleHar = path.join(unpackDir, 'flutter_embedding_compatible.har');
        const marker = path.join(unpackDir, '.sipon-api24-ready');
        if (!fs.existsSync(marker)) {
          fs.mkdirSync(unpackDir, { recursive: true });
          execFileSync('tar', ['-xzf', harPath, '-C', unpackDir]);
          const helperPath = path.join(packageDir, 'src', 'main', 'ets', 'plugin', 'editing',
            'OhosAutoFillHelper.ets');
          let helper = fs.readFileSync(helperPath, 'utf8');
          if (!helper.includes('AUTOFILL_SUPPORT_API = 26')) {
            throw new Error('Unexpected Flutter autofill source; review API compatibility before patching.');
          }
          const methodStart = helper.indexOf('  static requestAutoFill(');
          if (methodStart < 0) throw new Error('Flutter autofill helper has changed.');
          helper = helper.substring(0, methodStart)
            .replace(/autoFillManager\.AutoFillType/g, 'number')
            .replace(/autoFillManager\.ViewData/g, 'AutoFillManagerViewData') + `
  // API 26 request APIs are unavailable in the SDK used for this build.
  static requestAutoFill(
    _uiContext: UIContext, _viewData: OhosViewData, _autoFillType: number,
    _onSuccess: (values: Map<number, string>) => void,
    onFailure: (errCode: number) => void,
  ): void {
    onFailure(-1);
  }

  static requestAutoSave(
    _uiContext: UIContext, _viewData: OhosViewData,
    napiCallback: autoFillManager.AutoSaveCallback,
  ): void {
    napiCallback.onFailure();
  }
}
`;
          fs.writeFileSync(helperPath, helper);
          fs.writeFileSync(marker, hash);
        }
        if (!fs.existsSync(compatibleHar)) {
          execFileSync('tar', ['-czf', compatibleHar, '-C', unpackDir, 'package']);
        }
        overrides['@ohos/flutter_ohos'] = `file:${compatibleHar}`;
        appContext.setOverrides(overrides);
        console.info('Sipon: using a project-local Flutter embedding compatible with this SDK.');
      });
    }
  };
}
