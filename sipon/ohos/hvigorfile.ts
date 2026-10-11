import path from 'path'
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';
import { flutterSdkCompat } from './hvigor/flutter_sdk_compat';

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname)), flutterSdkCompat(path.dirname(__dirname))]
}
