// Project setup and the Android build, runnable from the command line:
//   Unity -batchmode -quit -projectPath unity -executeMethod Fatebound.EditorTools.BuildScript.BuildAndroid -logFile -
// Setup() (also Fatebound > Setup Project in the editor) makes the project match the Godot game's settings:
//  * URP asset + renderer (Assets/Fatebound/Settings/), forward rendering, HDR on, no URP post (the renderer runs
//    Godot's own post chain), main-light shadows one cascade 2048 px hard-edged to 50 m (siege_view.gd's _apply_hq),
//    per-pixel additional lights, no depth/opaque textures, SRP batcher
//  * linear colour space, Vulkan only, IL2CPP ARM64, sensor landscape (Godot's orientation 4), min SDK 25 (Unity 6's minimum)
//  * a boot scene (empty: Fatebound.Client.Boot starts the game from RuntimeInitializeOnLoadMethod)
// Environment (all optional): FB_ANDROID_PACKAGE (default com.fatebound.unityport -- installs beside the Godot
// preview), FB_VERSION_NAME, FB_VERSION_CODE, FB_OUTPUT (default Builds/Fatebound.apk; .aab builds an app bundle),
// FB_KEYSTORE / FB_KEYSTORE_PASS / FB_KEY_ALIAS / FB_KEY_PASS (default: Unity's debug key), FB_DEVELOPMENT=1.
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace Fatebound.EditorTools
{
    public static class BuildScript
    {
        const string SETTINGS = "Assets/Fatebound/Settings";
        const string URP_ASSET = SETTINGS + "/Fatebound_URP.asset";
        const string URP_RENDERER = SETTINGS + "/Fatebound_URP_Renderer.asset";
        const string BOOT_SCENE = "Assets/Fatebound/Boot.unity";

        static string Env(string name, string fallback)
        {
            var v = System.Environment.GetEnvironmentVariable(name);
            return string.IsNullOrEmpty(v) ? fallback : v;
        }

        [MenuItem("Fatebound/Setup Project")]
        public static void Setup()
        {
            Directory.CreateDirectory(SETTINGS);
            SetupUrp();
            SetupPlayer();
            SetupBootScene();
            AssetDatabase.SaveAssets();
            Debug.Log("Fatebound: project set up");
        }

        static void Set(SerializedObject so, string prop, Action<SerializedProperty> set)
        {
            var p = so.FindProperty(prop);
            if (p == null) { Debug.LogWarning("Fatebound setup: no URP field " + prop); return; }
            set(p);
        }

        // (URP's types by name: this file compiles without the URP assembly, which can only be built inside Unity)
        const string URP_ASM = ", Unity.RenderPipelines.Universal.Runtime";
        static readonly Type AssetType = Type.GetType("UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset" + URP_ASM);
        static readonly Type RendererType = Type.GetType("UnityEngine.Rendering.Universal.UniversalRendererData" + URP_ASM);

        static void SetupUrp()
        {
            if (AssetType == null || RendererType == null) throw new Exception("Fatebound setup: URP (com.unity.render-pipelines.universal) is missing");
            var asset = AssetDatabase.LoadAssetAtPath(URP_ASSET, AssetType) as RenderPipelineAsset;
            if (asset == null)
            {
                var renderer = ScriptableObject.CreateInstance(RendererType);
                AssetDatabase.CreateAsset(renderer, URP_RENDERER);
                var create = AssetType.GetMethod("Create", new[] { Type.GetType("UnityEngine.Rendering.Universal.ScriptableRendererData" + URP_ASM) });
                asset = (RenderPipelineAsset)create.Invoke(null, new object[] { renderer });
                AssetDatabase.CreateAsset(asset, URP_ASSET);
            }
            var rendererData = AssetDatabase.LoadAssetAtPath(URP_RENDERER, RendererType);
            if (rendererData != null)
            {
                var rso = new SerializedObject(rendererData);
                Set(rso, "m_RenderingMode", p => p.intValue = 0);                   // Forward
                Set(rso, "m_DepthPrimingMode", p => p.intValue = 0);                // Disabled
                Set(rso, "m_CopyDepthMode", p => p.intValue = 0);
                Set(rso, "postProcessData", p => p.objectReferenceValue = null);    // no URP post (Godot's runs instead)
                rso.ApplyModifiedPropertiesWithoutUndo();
                EditorUtility.SetDirty(rendererData);
            }
            var so = new SerializedObject(asset);
            Set(so, "m_SupportsHDR", p => p.boolValue = true);
            Set(so, "m_MSAA", p => p.intValue = 1);                                 // per viewport (render textures)
            Set(so, "m_RenderScale", p => p.floatValue = 1f);
            Set(so, "m_RequireDepthTexture", p => p.boolValue = false);
            // the opaque texture: the shockwave shader reads the screen behind it (Godot's hint_screen_texture), at half
            // resolution (a low-frequency distortion; Godot's copy is mipmapped and sampled at mip 0)
            Set(so, "m_RequireOpaqueTexture", p => p.boolValue = true);
            Set(so, "m_OpaqueDownsampling", p => p.intValue = 1);
            Set(so, "m_MainLightRenderingMode", p => p.intValue = 1);               // per pixel
            Set(so, "m_MainLightShadowsSupported", p => p.boolValue = true);
            Set(so, "m_MainLightShadowmapResolution", p => p.intValue = 2048);
            Set(so, "m_AdditionalLightsRenderingMode", p => p.intValue = 1);        // per pixel
            Set(so, "m_AdditionalLightsPerObjectLimit", p => p.intValue = 8);
            Set(so, "m_AdditionalLightShadowsSupported", p => p.boolValue = false);
            Set(so, "m_ShadowDistance", p => p.floatValue = 50f);
            Set(so, "m_ShadowCascadeCount", p => p.intValue = 1);
            Set(so, "m_SoftShadowsSupported", p => p.boolValue = false);
            Set(so, "m_ConservativeEnclosingSphere", p => p.boolValue = true);
            Set(so, "m_UseSRPBatcher", p => p.boolValue = true);
            Set(so, "m_SupportsDynamicBatching", p => p.boolValue = false);
            Set(so, "m_ColorGradingMode", p => p.intValue = 0);
            so.ApplyModifiedPropertiesWithoutUndo();
            EditorUtility.SetDirty(asset);
            GraphicsSettings.defaultRenderPipeline = asset;
            int levels = QualitySettings.names.Length;
            int current = QualitySettings.GetQualityLevel();
            for (int i = 0; i < levels; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = asset;
                QualitySettings.vSyncCount = 0;
                QualitySettings.antiAliasing = 0;
                QualitySettings.shadows = UnityEngine.ShadowQuality.HardOnly;
                QualitySettings.globalTextureMipmapLimit = 0;
                QualitySettings.anisotropicFiltering = AnisotropicFiltering.Disable;
            }
            QualitySettings.SetQualityLevel(current, false);
        }

        static void SetupPlayer()
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = "Fatebound";
            PlayerSettings.productName = "Fatebound";
            PlayerSettings.SetApplicationIdentifier(android, Env("FB_ANDROID_PACKAGE", "com.fatebound.unityport"));
            PlayerSettings.bundleVersion = Env("FB_VERSION_NAME", "0.32.0-unity");
            PlayerSettings.Android.bundleVersionCode = int.Parse(Env("FB_VERSION_CODE", "1"));
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.Vulkan });
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.SetManagedStrippingLevel(android, ManagedStrippingLevel.Minimal);
            PlayerSettings.SetApiCompatibilityLevel(android, ApiCompatibilityLevel.NET_Standard);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel25;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;
            PlayerSettings.Android.forceInternetPermission = true;
            PlayerSettings.Android.optimizedFramePacing = true;
            PlayerSettings.Android.startInFullscreen = true;
            PlayerSettings.Android.renderOutsideSafeArea = true;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.MTRendering = true;
            PlayerSettings.gpuSkinning = true;
            PlayerSettings.runInBackground = false;
            PlayerSettings.SplashScreen.backgroundColor = new Color(0.07f, 0.04f, 0.06f, 1f);   // Godot's boot_splash/bg_color
            // the app icon: Godot's config/icon
            var icon = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Resources/res/assets/branding/icon.png");
            if (icon != null) PlayerSettings.SetIcons(NamedBuildTarget.Unknown, new[] { icon }, IconKind.Any);
        }

        static void SetupBootScene()
        {
            if (!File.Exists(BOOT_SCENE))
            {
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, BOOT_SCENE);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(BOOT_SCENE, true) };
        }

        public static void BuildAndroid()
        {
            Setup();
            string output = Env("FB_OUTPUT", "Builds/Fatebound.apk");
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
            EditorUserBuildSettings.buildAppBundle = output.EndsWith(".aab", StringComparison.OrdinalIgnoreCase);
            string ks = Env("FB_KEYSTORE", "");
            if (ks.Length > 0)
            {
                PlayerSettings.Android.useCustomKeystore = true;
                PlayerSettings.Android.keystoreName = ks;
                PlayerSettings.Android.keystorePass = Env("FB_KEYSTORE_PASS", "");
                PlayerSettings.Android.keyaliasName = Env("FB_KEY_ALIAS", "");
                PlayerSettings.Android.keyaliasPass = Env("FB_KEY_PASS", "");
            }
            else PlayerSettings.Android.useCustomKeystore = false;
            var options = new BuildPlayerOptions
            {
                scenes = new[] { BOOT_SCENE },
                locationPathName = output,
                target = BuildTarget.Android,
                targetGroup = BuildTargetGroup.Android,
                options = Env("FB_DEVELOPMENT", "0") == "1" ? BuildOptions.Development : BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(options);
            Debug.Log("Fatebound build: " + report.summary.result + ", " + report.summary.totalSize + " bytes, " + report.summary.totalErrors + " errors -> " + output);
            if (Application.isBatchMode) EditorApplication.Exit(report.summary.result == BuildResult.Succeeded ? 0 : 1);
        }
    }
}
