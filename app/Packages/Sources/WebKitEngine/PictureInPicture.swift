import WebKit

/// The scripts that float a page's playing video and bring it back. They run in a world of their own, which
/// remembers the video they floated, so a video the user floated themselves is never brought back by Sela.
@MainActor
enum PictureInPictureScripts {
    static let world = WKContentWorld.world(name: "SelaPictureInPicture")

    /// Floats the largest video that's playing. Resolves to true when it floated.
    static let enter = """
        const playing = [...document.querySelectorAll("video")].filter((video) =>
            !video.paused && !video.ended && video.readyState > 2 && video.videoWidth > 0 && !video.disablePictureInPicture);
        if (playing.length === 0 || document.pictureInPictureElement) return false;
        const area = (video) => video.clientWidth * video.clientHeight;
        const video = playing.sort((a, b) => area(b) - area(a))[0];
        if (video.webkitPresentationMode && video.webkitPresentationMode !== "inline") return false;
        try {
            if (video.requestPictureInPicture) {
                await video.requestPictureInPicture();
            } else {
                video.webkitSetPresentationMode("picture-in-picture");
            }
        } catch {
            if (!video.webkitSetPresentationMode) return false;
            try { video.webkitSetPresentationMode("picture-in-picture"); } catch { return false; }
        }
        window.selaFloatedVideo = video;
        return true;
        """

    /// Brings back the video `enter` floated, if it still floats.
    static let exit = """
        const video = window.selaFloatedVideo;
        window.selaFloatedVideo = null;
        if (!video) return false;
        if (document.pictureInPictureElement === video) {
            await document.exitPictureInPicture();
        } else if (video.webkitPresentationMode === "picture-in-picture") {
            video.webkitSetPresentationMode("inline");
        }
        return true;
        """
}
