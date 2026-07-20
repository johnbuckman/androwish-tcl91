/*
 * build.gradle-fontcheck.groovy --
 *
 *	Paste this into build.gradle inside the android { } block, after the
 *	preBuild.doLast that (re)creates the assets symlinks.
 *
 *	Stock Tk 9.1 does not ship AndroWish's DejaVu/Symbola faces, and
 *	assets/sdl2tk9.1 is a symlink to jni/sdl2tk/library -- so replacing the
 *	Tk library tree silently drops the fonts.  The resulting failure is a
 *	startup panic in TkpGetFontFromAttributes ("cannot get any font"),
 *	which reads like a Tk bug rather than a missing build input.
 *
 *	It also checks the two license files, since the fonts are
 *	redistributed inside the APK.
 */

    /*
     * Verify the bundled fonts are staged.
     *
     * assets/sdl2tk9.1 is a symlink to jni/sdl2tk/library (recreated above),
     * so the fonts really live in jni/sdl2tk/library/fonts.  Stock Tk 9.1
     * does not ship them -- they are AndroWish's, and they have to be copied
     * across by hand when the Tk library tree is replaced.
     *
     * This is checked rather than assumed because the failure mode is awful:
     * with no fonts and no match, TkpGetFontFromAttributes panics with
     * "cannot get any font", which reads like a Tk bug rather than a missing
     * build input.  Fail here instead, with somewhere to go.
     */
    preBuild.doLast {
        def fontDir = file("${projectDir}/jni/sdl2tk/library/fonts")
        def required = [
            "DejaVuLGCSans.ttf", "DejaVuLGCSans-Bold.ttf",
            "DejaVuLGCSans-Oblique.ttf", "DejaVuLGCSans-BoldOblique.ttf",
            "DejaVuLGCSansMono.ttf", "DejaVuLGCSansMono-Bold.ttf",
            "DejaVuLGCSansMono-Oblique.ttf", "DejaVuLGCSansMono-BoldOblique.ttf",
            "DejaVuLGCSerif.ttf", "DejaVuLGCSerif-Bold.ttf",
            "DejaVuLGCSerif-Italic.ttf", "DejaVuLGCSerif-BoldItalic.ttf",
            "Symbola.ttf",
        ]
        def missing = required.findAll { !new File(fontDir, it).exists() }
        if (!missing.isEmpty()) {
            throw new GradleException(
                "Bundled fonts missing from ${fontDir}:\n" +
                "    " + missing.join("\n    ") + "\n\n" +
                "SdlTkListFonts()/MatchFont() resolve every generic family\n" +
                "(Helvetica, courier, times, ...) onto these faces.  Without\n" +
                "them the app panics at startup in TkpGetFontFromAttributes.\n" +
                "Copy them from an AndroWish 8.6 checkout's\n" +
                "jni/sdl2tk/library/fonts/, together with LICENSE.DejaVuLGC\n" +
                "and LICENSE.Symbola -- they are redistributed inside the APK.")
        }
        ["LICENSE.DejaVuLGC", "LICENSE.Symbola"].each {
            if (!file("${projectDir}/jni/sdl2tk/library/${it}").exists()) {
                throw new GradleException(
                    "jni/sdl2tk/library/${it} is missing.  The fonts are\n" +
                    "redistributed inside the APK, so their license text has\n" +
                    "to ship with them.")
            }
        }
        println "Bundled fonts OK (${required.size()} faces + 2 licenses)"
    }
