import { Promise } from "rsvp";
import { addComposerUploadPreProcessor } from "discourse/components/composer-editor";
import UppyMediaOptimization from "discourse/lib/uppy-media-optimization-plugin";

export default {
  initialize(owner) {
    const siteSettings = owner.lookup("service:site-settings");
    const capabilities = owner.lookup("service:capabilities");

    if (siteSettings.composer_media_optimization_image_enabled) {
      // Note that prior to v18, Safari has WASM memory growth bugs
      // eg https://github.com/emscripten-core/emscripten/issues/19144
      // this feature will need more work to be usable in Safari iOS
      // both before and after v18
      if (
        capabilities.isIOS &&
        !siteSettings.composer_ios_media_optimisation_image_enabled
      ) {
        return;
      }

      // Restrict feature to browsers that support OffscreenCanvas
      if (typeof OffscreenCanvas === "undefined") {
        return;
      }
      if (!("createImageBitmap" in self)) {
        return;
      }

      addComposerUploadPreProcessor(
        UppyMediaOptimization,
        ({ isMobileDevice }) => {
          return {
            optimizeFn: (data, opts) => {
              if (owner.isDestroyed || owner.isDestroying) {
                return Promise.resolve();
              }

              return owner
                .lookup("service:media-optimization-worker")
                .optimizeImage(data, opts);
            },
            runParallel: !isMobileDevice,
          };
        }
      );
    }
  },
};
