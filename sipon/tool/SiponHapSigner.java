import com.ohos.hapsigntool.HapSignTool;
import java.util.ArrayList;
import java.util.Arrays;

/** Supplies the local password in memory without placing it on the OS command line. */
class SiponHapSigner {
    public static void main(String[] args) {
        String password = System.getenv("SIPON_HAP_SIGN_PASSWORD");
        if (password == null || password.isEmpty()) {
            System.err.println("Missing signing password. Use Sign-Harmony-Release.cmd.");
            System.exit(1);
        }
        ArrayList<String> options = new ArrayList<>(Arrays.asList(args));
        options.addAll(Arrays.asList("-keystorePwd", password, "-keyPwd", password));
        HapSignTool.main(options.toArray(new String[0]));
    }
}
