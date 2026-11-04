/*
 * UAPI compatibility overlay for the FFmpeg HEVC short-term-RPS patch.
 *
 * Mainline headers as of Linux 6.18 do not define the Rockchip/upstream-review
 * HEVC extension controls used by the rkvdec stateless path.  The pinned
 * Quartz64-B kernel does.  This overlay adds only those definitions after the
 * real <linux/v4l2-controls.h>, so the Flatpak build does not need to replace
 * the SDK's kernel headers or copy the kernel tree.
 */

#ifndef Q64_V4L2_CONTROLS_OVERLAY_H
#define Q64_V4L2_CONTROLS_OVERLAY_H

#include_next <linux/v4l2-controls.h>

#ifndef V4L2_CID_STATELESS_HEVC_EXT_SPS_ST_RPS
#define V4L2_CID_STATELESS_HEVC_EXT_SPS_ST_RPS  (V4L2_CID_CODEC_STATELESS_BASE + 408)
#define V4L2_CID_STATELESS_HEVC_EXT_SPS_LT_RPS  (V4L2_CID_CODEC_STATELESS_BASE + 409)

#define V4L2_HEVC_EXT_SPS_ST_RPS_FLAG_INTER_REF_PIC_SET_PRED	0x1

struct v4l2_ctrl_hevc_ext_sps_st_rps {
	__u8	delta_idx_minus1;
	__u8	delta_rps_sign;
	__u8	num_negative_pics;
	__u8	num_positive_pics;
	__u32	used_by_curr_pic;
	__u32	use_delta_flag;
	__u16	abs_delta_rps_minus1;
	__u16	delta_poc_s0_minus1[16];
	__u16	delta_poc_s1_minus1[16];
	__u16	flags;
};

struct v4l2_ctrl_hevc_ext_sps_lt_rps {
	__u16	lt_ref_pic_poc_lsb_sps;
	__u16	flags;
};
#endif /* !V4L2_CID_STATELESS_HEVC_EXT_SPS_ST_RPS */

#endif /* Q64_V4L2_CONTROLS_OVERLAY_H */
