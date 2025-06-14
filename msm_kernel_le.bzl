load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "//build:msm_kernel_extensions.bzl",
    "define_extras",
    "get_build_config_fragments",
    "get_dtb_list",
    "get_dtbo_list",
    "get_dtstree",
    "get_gki_ramdisk_prebuilt_binary",
    "get_vendor_ramdisk_binaries",
)
load("//build/bazel_common_rules/dist:dist.bzl", "copy_to_dist_dir")
load("//build/kernel/kleaf:constants.bzl", "aarch64_outs")
load(
    "//build/kernel/kleaf:kernel.bzl",
    "kernel_build",
    "kernel_build_config",
    "kernel_compile_commands",
    "kernel_images",
    "kernel_modules_install",
    "kernel_uapi_headers_cc_library",
    "merged_kernel_uapi_headers",
)
load(":allyes_images.bzl", "gen_allyes_files")
load(":image_opts.bzl", "boot_image_opts")
load(":modules.bzl", "get_gki_modules_list")
load(":msm_abl.bzl", "define_abl_dist")
load(":msm_common.bzl", "define_top_level_config", "gen_config_without_source_lines", "get_out_dir")
load(":msm_dtc.bzl", "define_dtc_dist")
load(":target_variants.bzl", "le_variants")

def _define_build_config(
        msm_target,
        target,
        variant,
        defconfig,
        target_arch,
        target_variants,
        boot_image_opts = boot_image_opts(),
        build_config_fragments = []):
    """Creates a kernel_build_config for an MSM target

    Creates a `kernel_build_config` for input to a `kernel_build` rule.

    Args:
      msm_target: name of target platform (e.g. "kalama")
      variant: variant of kernel to build (e.g. "gki")
    """

    # keep earlycon addr in earlycon cmdline param only when provided explicitly in target's bazel file
    # otherwise, rely on stdout-path
    earlycon_param = "={}".format(boot_image_opts.earlycon_addr) if boot_image_opts.earlycon_addr != None else ""
    earlycon_param = "earlycon" + earlycon_param

    write_file(
        name = "{}_build_config_bazel".format(target),
        out = "build.config.msm.{}.generated".format(target),
        content = [
            'KERNEL_DIR="msm-kernel"',
            "VARIANTS=({})".format(" ".join([v.replace("-", "_") for v in target_variants])),
            "MSM_ARCH={}".format(msm_target.replace("-", "_")),
            "VARIANT={}".format(variant.replace("-", "_")),
            "ABL_SRC=bootable/bootloader/edk2",
            "BOOT_IMAGE_HEADER_VERSION={}".format(boot_image_opts.boot_image_header_version),
            "BASE_ADDRESS=0x%X" % boot_image_opts.base_address,
            "PAGE_SIZE={}".format(boot_image_opts.page_size),
            "TARGET_HAS_SEPARATE_RD=1",
            "PREFERRED_USERSPACE=le",
            "BUILD_BOOT_IMG=1",
            "BUILD_INITRAMFS=1",
            '[ -z "$DT_OVERLAY_SUPPORT" ] && DT_OVERLAY_SUPPORT=1',
            '[ "$KERNEL_CMDLINE_CONSOLE_AUTO" != "0" ] && KERNEL_VENDOR_CMDLINE+=\' console=ttyMSM0,115200n8 {} qcom_geni_serial.con_enabled=1 \''.format(earlycon_param),
            "KERNEL_VENDOR_CMDLINE+=' {} '".format(" ".join(boot_image_opts.kernel_vendor_cmdline_extras)),
            "VENDOR_BOOTCONFIG+='androidboot.first_stage_console=1 androidboot.hardware=qcom_kp'",
            "",  # Needed for newline at end of file
        ],
    )

    top_level_config = define_top_level_config(target)
    common_config = gen_config_without_source_lines("build.config.common", target)

    if target_arch == "arm64":
        target_arch = "aarch64"

    # Concatenate build config fragments to form the final config
    kernel_build_config(
        name = "{}_build_config".format(target),
        srcs = [
            # do not sort
            top_level_config,
            "build.config.constants",
            common_config,
            ":build.config.{}".format(target_arch),
            ":{}_build_config_bazel".format(target),
        ] + [fragment for fragment in build_config_fragments] + [
            "build.config.msm.common",
            defconfig,
        ],
    )

def _define_kernel_build(
        target,
        in_tree_module_list,
        dtb_list,
        dtbo_list,
        dtstree,
        target_arch):
    """Creates a `kernel_build` and other associated definitions

    This is where the main kernel build target is created (e.g. `//msm-kernel:kalama_gki`).
    Many other rules will take this `kernel_build` as an input.

    Args:
      target: name of main Bazel target (e.g. `kalama_gki`)
      in_tree_module_list: list of in-tree modules
      dtb_list: device tree blobs expected to be built
      dtbo_list: device tree overlay blobs expected to be built
    """
    out_list = [".config", "Module.symvers"]

    if dtb_list:
        out_list += dtb_list
    if dtbo_list:
        out_list += dtbo_list

    # Add basic kernel outputs
    out_list += aarch64_outs

    if target.split("_")[0] == "pineapple-le" or target.split("_")[0] == "neo-le":
        out_list += ["utsrelease.h"] + ["certs/signing_key.x509"] + ["certs/signing_key.pem"] + ["scripts/sign-file"]
    elif target_arch == "arm":
        out_list += ["zImage"] + ["module.lds"] + ["utsrelease.h"]
        out_list += ["scripts/sign-file"] + ["certs/signing_key.x509"] + ["certs/signing_key.pem"]

    # LE builds don't build compressed, so remove from list
    out_list.remove("Image.lz4")
    out_list.remove("Image.gz")

    if target.split("_")[0] == "pineapple-le" or target.split("_")[0] == "neo-le":
        in_tree_module_list = in_tree_module_list + get_gki_modules_list("arm64")

    kernel_build(
        name = target,
        arch = target_arch,
        module_outs = in_tree_module_list,
        outs = out_list,
        build_config = ":{}_build_config".format(target),
        dtstree = dtstree,
        kmi_symbol_list = None,
        additional_kmi_symbol_lists = None,
        abi_definition = None,
        visibility = ["//visibility:public"],
    )

    kernel_modules_install(
        name = "{}_modules_install".format(target),
        kernel_build = ":{}".format(target),
    )

    merged_kernel_uapi_headers(
        name = "{}_merged_kernel_uapi_headers".format(target),
        kernel_build = ":{}".format(target),
    )

    kernel_compile_commands(
        name = "{}_compile_commands".format(target),
        kernel_build = ":{}".format(target),
    )

def _define_kernel_dist(target, msm_target, variant):
    """Creates distribution targets for kernel builds

    When Bazel builds everything, the outputs end up buried in `bazel-bin`.
    These rules are used to copy the build artifacts to `out/msm-kernel-<target>/dist/`
    with proper permissions, etc.

    Args:
      target: name of main Bazel target (e.g. `kalama_gki`)
    """

    dist_dir = get_out_dir(msm_target, variant) + "/dist"
    le_target = msm_target.split("-")[0]

    msm_dist_targets = [
        # do not sort
        ":{}".format(target),
        ":{}_images".format(target),
        ":{}_merged_kernel_uapi_headers".format(target),
        ":{}_build_config".format(target),
    ]

    if msm_target == "mdm9607" or target.split("_")[0] == "pineapple-le" or target.split("_")[0] == "neo-le":
        msm_dist_targets += [
            ":verity_key",
        ]
    else:
        msm_dist_targets += [
            ":{}_dummy_files".format(le_target),
            ":{}_avb_sign_boot_image".format(target),
            "//msm-kernel:{}_super_image".format(le_target + "_gki"),
        ]

    copy_to_dist_dir(
        name = "{}_dist".format(target),
        data = msm_dist_targets,
        dist_dir = dist_dir,
        flat = True,
        wipe_dist_dir = True,
        allow_duplicate_filenames = True,
        mode_overrides = {
            # do not sort
            "**/*.elf": "755",
            "**/vmlinux": "755",
            "**/Image": "755",
            "**/*.dtb*": "755",
            "**/LinuxLoader*": "755",
            "**/sign-file": "755",
            "**/*": "644",
        },
        log = "info",
    )

def _define_uapi_library(target):
    """Define a cc_library for userspace programs to use

    Args:
      target: kernel_build target name (e.g. "kalama_gki")
    """
    kernel_uapi_headers_cc_library(
        name = "{}_uapi_header_library".format(target),
        kernel_build = ":{}".format(target),
    )

def _define_image_build(
        msm_target,
        target,
        in_tree_module_list,
        dtbo_list,
        vendor_ramdisk_binaries):
    kernel_images(
        name = "{}_images".format(target),
        kernel_modules_install = ":{}_modules_install".format(target),
        kernel_build = ":{}".format(target),
        build_boot = True,
        build_dtbo = True if dtbo_list else False,
        build_initramfs = True,
        build_vendor_boot = True,
        build_vendor_kernel_boot = False,
        build_vendor_dlkm = True,
        build_system_dlkm = True,
        modules_list = "modules.list.msm.{}".format(msm_target),
        system_dlkm_modules_list = "android/gki_system_dlkm_modules",
        vendor_dlkm_modules_list = ":{}_vendor_dlkm_modules_list_generated".format(target),
        system_dlkm_modules_blocklist = "modules.systemdlkm_blocklist.msm.{}".format(msm_target),
        vendor_dlkm_modules_blocklist = "modules.vendor_blocklist.msm.{}".format(msm_target),
        dtbo_srcs = [":{}/".format(target) + d for d in dtbo_list] if dtbo_list else None,
        vendor_ramdisk_binaries = vendor_ramdisk_binaries,
        gki_ramdisk_prebuilt_binary = get_gki_ramdisk_prebuilt_binary(),
        boot_image_outs = ["boot.img", "init_boot.img", "dtb.img", "vendor_boot.img"],
        deps = [
            "modules.list.msm.{}".format(msm_target),
            "modules.vendor_blocklist.msm.{}".format(msm_target),
            "modules.systemdlkm_blocklist.msm.{}".format(msm_target),
            "android/gki_system_dlkm_modules",
        ],
    )

    native.genrule(
        name = "{}_system_dlkm_module_blocklist".format(target),
        srcs = ["modules.systemdlkm_blocklist.msm.{}".format(msm_target)],
        outs = ["{}/system_dlkm.modules.blocklist".format(target)],
        cmd = """
          mkdir -p "$$(dirname "$@")"
          sed -e '/^#/d' -e '/^$$/d' $(SRCS) > "$@"
        """,
    )

    native.filegroup(
        name = "{}_system_dlkm_image_file".format(target),
        srcs = ["{}_images".format(target)],
        output_group = "system_dlkm.img",
    )

    # Generate the vendor_dlkm list
    native.genrule(
        name = "{}_vendor_dlkm_modules_list_generated".format(target),
        srcs = [],
        outs = ["modules.list.vendor_dlkm.{}".format(target)],
        cmd_bash = """
          touch "$@"
          for module in {mod_list}; do
            basename "$$module" >> "$@"
          done
        """.format(mod_list = " ".join(in_tree_module_list)),
    )

    native.filegroup(
        name = "{}_vendor_dlkm_image_file".format(target),
        srcs = [":{}_images".format(target)],
        output_group = "vendor_dlkm.img",
    )

def define_msm_le(
        msm_target,
        variant,
        defconfig,
        in_tree_module_list,
        target_arch = "arm64",
        target_variants = le_variants,
        boot_image_opts = boot_image_opts()):
    """Top-level kernel build definition macro for an MSM platform

    Args:
      msm_target: name of target platform (e.g. "pineapple.allyes")
      variant: variant of kernel to build (e.g. "gki")
      in_tree_module_list: list of in-tree modules
      boot_image_header_version: boot image header version (for `boot.img`)
      base_address: edk2 base address
      page_size: kernel page size
      super_image_size: size of super image partition
      lz4_ramdisk: whether to use an lz4-compressed ramdisk
    """

    if not variant in target_variants:
        fail("{} not defined in target_variants.bzl le_variants!".format(variant))

    # Enforce format of "//msm-kernel:target-foo_variant-bar" (underscore is the delimeter
    # between target and variant)
    target = msm_target.replace("_", "-") + "_" + variant.replace("_", "-")
    le_target = msm_target.split("-")[0]

    dtb_list = get_dtb_list(le_target)
    dtbo_list = get_dtbo_list(le_target)
    dtstree = get_dtstree(le_target, target_arch)

    vendor_ramdisk_binaries = get_vendor_ramdisk_binaries(target, flavor = "le")
    build_config_fragments = get_build_config_fragments(le_target)

    _define_build_config(
        le_target,
        target,
        variant,
        defconfig,
        target_arch,
        target_variants,
        boot_image_opts = boot_image_opts,
        build_config_fragments = build_config_fragments,
    )

    _define_kernel_build(
        target,
        in_tree_module_list,
        dtb_list,
        dtbo_list,
        dtstree,
        target_arch,
    )

    if msm_target != "neo" or msm_target != "neo-le":
        kernel_images(
            name = "{}_images".format(target),
            kernel_modules_install = ":{}_modules_install".format(target),
            kernel_build = ":{}".format(target),
            build_boot = True,
            build_dtbo = True if dtbo_list else False,
            build_initramfs = True,
            dtbo_srcs = [":{}/".format(target) + d for d in dtbo_list] if dtbo_list else None,
            vendor_ramdisk_binaries = vendor_ramdisk_binaries,
            boot_image_outs = ["boot.img"],
        )
    else:
        _define_image_build(
            msm_target,
            target,
            in_tree_module_list,
            dtbo_list,
            vendor_ramdisk_binaries,
        )

    _define_uapi_library(target)

    _define_kernel_dist(target, msm_target, variant)

    define_abl_dist(target, msm_target, variant)

    define_dtc_dist(target, msm_target, variant)
    if msm_target == "pineapple-le" or msm_target == "neo-le":
        define_extras(target)
        return
    gen_allyes_files(le_target, target)

    define_extras(target)
