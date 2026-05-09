#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <dlfcn.h>

typedef int HI_S32;
typedef unsigned int HI_U32;
typedef unsigned char HI_U8;
typedef char HI_CHAR;
typedef enum { HI_FALSE = 0, HI_TRUE = 1 } HI_BOOL;

#define HI_SUCCESS 0
#define VO_DEV_HD 0
#define VO_LAYER_VID 0
#define HDMI_ID_0 0

typedef enum {
    VO_INTF_CVBS = 0x01, VO_INTF_YPBPR = 0x02, VO_INTF_VGA = 0x04,
    VO_INTF_HDMI = 0x08, VO_INTF_BT656 = 0x10, VO_INTF_BT1120 = 0x20,
    VO_INTF_LCD = 0x40,
} VO_INTF_TYPE_E;

typedef enum {
    VO_OUTPUT_PAL = 0, VO_OUTPUT_NTSC = 1, VO_OUTPUT_1080P24 = 2,
    VO_OUTPUT_1080P25 = 3, VO_OUTPUT_1080P30 = 4, VO_OUTPUT_720P50 = 5,
    VO_OUTPUT_720P60 = 6, VO_OUTPUT_1080I50 = 7, VO_OUTPUT_1080I60 = 8,
    VO_OUTPUT_1080P50 = 9, VO_OUTPUT_1080P60 = 10, VO_OUTPUT_576P50 = 11,
    VO_OUTPUT_480P60 = 12,
} VO_INTF_SYNC_E;

typedef struct { HI_S32 s32X; HI_S32 s32Y; HI_U32 u32Width; HI_U32 u32Height; } RECT_S;
typedef struct { HI_U32 u32Width; HI_U32 u32Height; } SIZE_S;

typedef struct {
    VO_INTF_TYPE_E enIntfType;
    VO_INTF_SYNC_E enIntfSync;
    HI_U32 u32BgColor;
} VO_PUB_ATTR_S;

typedef struct {
    RECT_S stDispRect;
    SIZE_S stImageSize;
    HI_U32 u32DispFrmRt;
    HI_S32 enPixFormat;
} VO_VIDEO_LAYER_ATTR_S;

typedef enum {
    HDMI_VIDEO_FMT_1080P_60 = 0, HDMI_VIDEO_FMT_1080P_50,
    HDMI_VIDEO_FMT_1080P_30, HDMI_VIDEO_FMT_1080P_25,
    HDMI_VIDEO_FMT_1080P_24, HDMI_VIDEO_FMT_1080I_60,
    HDMI_VIDEO_FMT_1080I_50, HDMI_VIDEO_FMT_720P_60,
    HDMI_VIDEO_FMT_720P_50, HDMI_VIDEO_FMT_576P_50,
    HDMI_VIDEO_FMT_480P_60,
} HDMI_VIDEO_FMT_E;

typedef enum { HDMI_SOUND_INTF_I2S = 0, HDMI_SOUND_INTF_SPDIF } HDMI_SOUND_INTF_E;
typedef enum { HDMI_DEEP_COLOR_24BIT = 0, HDMI_DEEP_COLOR_30BIT, HDMI_DEEP_COLOR_36BIT } HDMI_DEEP_COLOR_E;
typedef enum { HDMI_SAMPLE_RATE_48K = 0, HDMI_SAMPLE_RATE_44K, HDMI_SAMPLE_RATE_32K } HDMI_SAMPLE_RATE_E;

typedef struct { HDMI_SAMPLE_RATE_E enSampleRate; HI_U8 u8BitDepth; } HDMI_SOUND_ATTR_S;

typedef struct {
    HDMI_VIDEO_FMT_E enVideoFmt;
    HDMI_VIDEO_FMT_E enVidOut;
    HDMI_SOUND_INTF_E enSoundIntf;
    HI_BOOL bEnable;
    HI_BOOL bAuthMode;
    HDMI_DEEP_COLOR_E enDeepColorMode;
    HDMI_SOUND_ATTR_S stSoundAttr;
} HDMI_ATTR_S;

typedef HI_S32 (*FN_SYS_Init)(void);
typedef HI_S32 (*FN_SYS_Exit)(void);
typedef HI_S32 (*FN_VO_SetPubAttr)(int, VO_PUB_ATTR_S*);
typedef HI_S32 (*FN_VO_Enable)(int);
typedef HI_S32 (*FN_VO_Disable)(int);
typedef HI_S32 (*FN_VO_SetVideoLayerAttr)(int, VO_VIDEO_LAYER_ATTR_S*);
typedef HI_S32 (*FN_VO_EnableVideoLayer)(int);
typedef HI_S32 (*FN_VO_DisableVideoLayer)(int);
typedef HI_S32 (*FN_HDMI_Open)(int);
typedef HI_S32 (*FN_HDMI_Close)(int);
typedef HI_S32 (*FN_HDMI_GetAttr)(int, HDMI_ATTR_S*);
typedef HI_S32 (*FN_HDMI_SetAttr)(int, HDMI_ATTR_S*);
typedef HI_S32 (*FN_HDMI_Start)(int);
typedef HI_S32 (*FN_HDMI_Stop)(int);

static volatile int g_run = 1;
void sig_handler(int sig) { g_run = 0; }

VO_INTF_SYNC_E get_vo_sync(const char *res) {
    if (!res || strcmp(res, "1080p60") == 0) return VO_OUTPUT_1080P60;
    if (strcmp(res, "1080p50") == 0) return VO_OUTPUT_1080P50;
    if (strcmp(res, "720p60") == 0) return VO_OUTPUT_720P60;
    if (strcmp(res, "720p50") == 0) return VO_OUTPUT_720P50;
    if (strcmp(res, "480p60") == 0) return VO_OUTPUT_480P60;
    if (strcmp(res, "576p50") == 0) return VO_OUTPUT_576P50;
    return VO_OUTPUT_1080P60;
}

HDMI_VIDEO_FMT_E get_hdmi_fmt(VO_INTF_SYNC_E sync) {
    switch (sync) {
        case VO_OUTPUT_1080P60: return HDMI_VIDEO_FMT_1080P_60;
        case VO_OUTPUT_1080P50: return HDMI_VIDEO_FMT_1080P_50;
        case VO_OUTPUT_720P60:  return HDMI_VIDEO_FMT_720P_60;
        case VO_OUTPUT_720P50:  return HDMI_VIDEO_FMT_720P_50;
        case VO_OUTPUT_480P60:  return HDMI_VIDEO_FMT_480P_60;
        case VO_OUTPUT_576P50:  return HDMI_VIDEO_FMT_576P_50;
        default: return HDMI_VIDEO_FMT_1080P_60;
    }
}

void get_resolution(VO_INTF_SYNC_E sync, HI_U32 *w, HI_U32 *h) {
    switch (sync) {
        case VO_OUTPUT_1080P60: case VO_OUTPUT_1080P50: *w=1920; *h=1080; break;
        case VO_OUTPUT_720P60:  case VO_OUTPUT_720P50:  *w=1280; *h=720;  break;
        case VO_OUTPUT_480P60:  *w=720;  *h=480;  break;
        case VO_OUTPUT_576P50:  *w=720;  *h=576;  break;
        default: *w=1920; *h=1080; break;
    }
}

int main(int argc, char *argv[])
{
    const char *resolution = "1080p60";
    int daemon_mode = 0;
    int keep_display = 1;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-d") == 0) daemon_mode = 1;
        else if (strcmp(argv[i], "--cleanup") == 0) keep_display = 0;
        else resolution = argv[i];
    }

    printf("Hi3798MV100 Display Init - Resolution: %s, KeepDisplay: %s\n",
           resolution, keep_display ? "YES" : "NO");

    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    const char *sdk_lib_paths[] = {
        "/opt/hisilicon/lib",
        "/usr/local/lib",
        "/usr/lib",
        NULL
    };

    for (int i = 0; sdk_lib_paths[i]; i++) {
        char path[256];
        snprintf(path, sizeof(path), "%s/libpthread.so.0", sdk_lib_paths[i]);
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (h) { printf("Preloaded %s\n", path); break; }
    }
    for (int i = 0; sdk_lib_paths[i]; i++) {
        char path[256];
        snprintf(path, sizeof(path), "%s/libdl.so.2", sdk_lib_paths[i]);
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (h) { printf("Preloaded %s\n", path); break; }
    }
    for (int i = 0; sdk_lib_paths[i]; i++) {
        char path[256];
        snprintf(path, sizeof(path), "%s/librt.so.1", sdk_lib_paths[i]);
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (h) { printf("Preloaded %s\n", path); break; }
    }

    void *lib_msp = dlopen("libhi_msp.so", RTLD_NOW);
    if (!lib_msp) {
        lib_msp = dlopen("/opt/hisilicon/lib/libhi_msp.so", RTLD_NOW);
    }
    if (!lib_msp) {
        lib_msp = dlopen("/usr/lib/libhi_msp.so", RTLD_NOW);
    }
    if (!lib_msp) {
        lib_msp = dlopen("/usr/local/lib/libhi_msp.so", RTLD_NOW);
    }
    if (!lib_msp) {
        printf("ERROR: Cannot load libhi_msp.so: %s\n", dlerror());
        printf("Please install SDK libraries to /opt/hisilicon/lib/ or /usr/lib/\n");
        return 1;
    }
    printf("Loaded libhi_msp.so\n");

    FN_SYS_Init pSYS_Init = (FN_SYS_Init)dlsym(lib_msp, "HI_MPI_SYS_Init");
    FN_SYS_Exit pSYS_Exit = (FN_SYS_Exit)dlsym(lib_msp, "HI_MPI_SYS_Exit");
    FN_VO_SetPubAttr pVO_SetPubAttr = (FN_VO_SetPubAttr)dlsym(lib_msp, "HI_MPI_VO_SetPubAttr");
    FN_VO_Enable pVO_Enable = (FN_VO_Enable)dlsym(lib_msp, "HI_MPI_VO_Enable");
    FN_VO_Disable pVO_Disable = (FN_VO_Disable)dlsym(lib_msp, "HI_MPI_VO_Disable");
    FN_VO_SetVideoLayerAttr pVO_SetVideoLayerAttr = (FN_VO_SetVideoLayerAttr)dlsym(lib_msp, "HI_MPI_VO_SetVideoLayerAttr");
    FN_VO_EnableVideoLayer pVO_EnableVideoLayer = (FN_VO_EnableVideoLayer)dlsym(lib_msp, "HI_MPI_VO_EnableVideoLayer");
    FN_VO_DisableVideoLayer pVO_DisableVideoLayer = (FN_VO_DisableVideoLayer)dlsym(lib_msp, "HI_MPI_VO_DisableVideoLayer");
    FN_HDMI_Open pHDMI_Open = (FN_HDMI_Open)dlsym(lib_msp, "HI_MPI_HDMI_Open");
    FN_HDMI_Close pHDMI_Close = (FN_HDMI_Close)dlsym(lib_msp, "HI_MPI_HDMI_Close");
    FN_HDMI_GetAttr pHDMI_GetAttr = (FN_HDMI_GetAttr)dlsym(lib_msp, "HI_MPI_HDMI_GetAttr");
    FN_HDMI_SetAttr pHDMI_SetAttr = (FN_HDMI_SetAttr)dlsym(lib_msp, "HI_MPI_HDMI_SetAttr");
    FN_HDMI_Start pHDMI_Start = (FN_HDMI_Start)dlsym(lib_msp, "HI_MPI_HDMI_Start");
    FN_HDMI_Stop pHDMI_Stop = (FN_HDMI_Stop)dlsym(lib_msp, "HI_MPI_HDMI_Stop");

    if (!pSYS_Init || !pVO_SetPubAttr || !pVO_Enable || !pHDMI_Open || !pHDMI_Start) {
        printf("ERROR: Cannot resolve MPP API symbols: %s\n", dlerror());
        dlclose(lib_msp);
        return 1;
    }

    HI_S32 s32Ret;
    int vo_enabled = 0, layer_enabled = 0, hdmi_opened = 0, hdmi_started = 0;
    VO_INTF_SYNC_E vo_sync = get_vo_sync(resolution);
    HDMI_VIDEO_FMT_E hdmi_fmt = get_hdmi_fmt(vo_sync);
    HI_U32 width, height;
    get_resolution(vo_sync, &width, &height);
    printf("VO sync=%d, HDMI fmt=%d, %ux%u\n", vo_sync, hdmi_fmt, width, height);

    s32Ret = pSYS_Init();
    if (s32Ret != HI_SUCCESS) { printf("HI_MPI_SYS_Init failed: 0x%x\n", s32Ret); dlclose(lib_msp); return 1; }
    printf("SYS_Init OK\n");

    VO_PUB_ATTR_S stPubAttr;
    memset(&stPubAttr, 0, sizeof(stPubAttr));
    stPubAttr.enIntfType = VO_INTF_HDMI;
    stPubAttr.enIntfSync = vo_sync;
    stPubAttr.u32BgColor = 0x00000000;

    s32Ret = pVO_SetPubAttr(VO_DEV_HD, &stPubAttr);
    if (s32Ret != HI_SUCCESS) { printf("VO_SetPubAttr failed: 0x%x\n", s32Ret); goto cleanup; }
    printf("VO_SetPubAttr OK\n");

    s32Ret = pVO_Enable(VO_DEV_HD);
    if (s32Ret != HI_SUCCESS) { printf("VO_Enable failed: 0x%x\n", s32Ret); goto cleanup; }
    vo_enabled = 1;
    printf("VO_Enable OK\n");

    VO_VIDEO_LAYER_ATTR_S stLayerAttr;
    memset(&stLayerAttr, 0, sizeof(stLayerAttr));
    stLayerAttr.stDispRect.s32X = 0;
    stLayerAttr.stDispRect.s32Y = 0;
    stLayerAttr.stDispRect.u32Width = width;
    stLayerAttr.stDispRect.u32Height = height;
    stLayerAttr.stImageSize.u32Width = width;
    stLayerAttr.stImageSize.u32Height = height;
    stLayerAttr.u32DispFrmRt = 60;
    stLayerAttr.enPixFormat = 0;

    s32Ret = pVO_SetVideoLayerAttr(VO_LAYER_VID, &stLayerAttr);
    if (s32Ret != HI_SUCCESS) { printf("VO_SetVideoLayerAttr failed: 0x%x\n", s32Ret); goto cleanup; }
    printf("VO_SetVideoLayerAttr OK\n");

    s32Ret = pVO_EnableVideoLayer(VO_LAYER_VID);
    if (s32Ret != HI_SUCCESS) { printf("VO_EnableVideoLayer failed: 0x%x\n", s32Ret); goto cleanup; }
    layer_enabled = 1;
    printf("VO_EnableVideoLayer OK\n");

    s32Ret = pHDMI_Open(HDMI_ID_0);
    if (s32Ret != HI_SUCCESS) { printf("HDMI_Open failed: 0x%x\n", s32Ret); goto cleanup; }
    hdmi_opened = 1;
    printf("HDMI_Open OK\n");

    if (pHDMI_GetAttr && pHDMI_SetAttr) {
        HDMI_ATTR_S stHdmiAttr;
        memset(&stHdmiAttr, 0, sizeof(stHdmiAttr));
        s32Ret = pHDMI_GetAttr(HDMI_ID_0, &stHdmiAttr);
        if (s32Ret == HI_SUCCESS) {
            stHdmiAttr.enVideoFmt = hdmi_fmt;
            stHdmiAttr.enVidOut = hdmi_fmt;
            stHdmiAttr.enSoundIntf = HDMI_SOUND_INTF_I2S;
            stHdmiAttr.bEnable = HI_TRUE;
            stHdmiAttr.bAuthMode = HI_FALSE;
            stHdmiAttr.enDeepColorMode = HDMI_DEEP_COLOR_24BIT;
            stHdmiAttr.stSoundAttr.enSampleRate = HDMI_SAMPLE_RATE_48K;
            stHdmiAttr.stSoundAttr.u8BitDepth = 16;
            s32Ret = pHDMI_SetAttr(HDMI_ID_0, &stHdmiAttr);
            if (s32Ret != HI_SUCCESS) printf("HDMI_SetAttr failed: 0x%x (continuing)\n", s32Ret);
            else printf("HDMI_SetAttr OK\n");
        } else {
            printf("HDMI_GetAttr failed: 0x%x (trying direct set)\n", s32Ret);
        }
    }

    s32Ret = pHDMI_Start(HDMI_ID_0);
    if (s32Ret != HI_SUCCESS) { printf("HDMI_Start failed: 0x%x\n", s32Ret); goto cleanup; }
    hdmi_started = 1;
    printf("HDMI_Start OK\n");

    printf("\n=== Display initialized: %s %ux%u via HDMI ===\n", resolution, width, height);

    if (daemon_mode) {
        printf("Running in daemon mode. Press Ctrl+C to stop.\n");
        while (g_run) { sleep(1); }
        printf("Shutting down display...\n");
        keep_display = 0;
    } else if (keep_display) {
        printf("Display init complete. Display will remain active after exit.\n");
        printf("Use --cleanup flag to deinitialize display on exit.\n");
        dlclose(lib_msp);
        return 0;
    } else {
        printf("Display init complete. Cleaning up in 5 seconds (--cleanup mode)...\n");
        sleep(5);
    }

cleanup:
    if (!keep_display || !hdmi_started) {
        if (hdmi_started && pHDMI_Stop) pHDMI_Stop(HDMI_ID_0);
        if (hdmi_opened && pHDMI_Close) pHDMI_Close(HDMI_ID_0);
        if (layer_enabled && pVO_DisableVideoLayer) pVO_DisableVideoLayer(VO_LAYER_VID);
        if (vo_enabled && pVO_Disable) pVO_Disable(VO_DEV_HD);
        if (pSYS_Exit) pSYS_Exit();
        printf("Display deinitialized.\n");
    }

    dlclose(lib_msp);
    printf("Done.\n");
    return (hdmi_started && keep_display) ? 0 : 1;
}
