#!/usr/bin/env bash

set -eu -o pipefail

print_usage() {
	echo -e "Usage:\n${0} build|clean|reset-template"
}

if [ -z ${1+x} ]; then
	print_usage
	exit 0
elif [ "$1" = "clean" ]; then
	rm -rf temp/tmp.* build.md build
	reset_template
	exit 0
elif [ "$1" = "reset-template" ]; then
	reset_template
	exit 0
elif [ "$1" = "build" ]; then
	:
else
	print_usage
	exit 1
fi

source utils.sh
trap "rm -rf temp/tmp.*" INT

: >build.md
mkdir -p "$BUILD_DIR" "$TEMP_DIR"

toml_prep "$(cat config.toml)"
read_main_config

if [ "$UPDATE_PREBUILTS" = true ]; then get_prebuilts; else set_prebuilts; fi
reset_template
get_cmpr

if ((COMPRESSION_LEVEL > 9)) || ((COMPRESSION_LEVEL < 1)); then
	abort "COMPRESSION_LEVEL must be between 1 and 9"
fi
if [ "$BUILD_MINDETACH_MODULE" = true ]; then : >$PKGS_LIST; fi

# building from config
log "**App Versions:**"
for t in $(toml_get_all_tables); do
	if [ "$t" = main-config ]; then continue; fi
	enabled=$(toml_get "$t" enabled) || enabled=true
	if [ "$enabled" = false ]; then continue; fi

	declare -A app_args
	merge_integrations=$(toml_get "$t" merge-integrations) || merge_integrations=false
	excluded_patches=$(toml_get "$t" excluded-patches) || excluded_patches=""
	included_patches=$(toml_get "$t" included-patches) || included_patches=""
	exclusive_patches=$(toml_get "$t" exclusive-patches) || exclusive_patches=false
	app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
	app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$t
	app_args[allow_alpha_version]=$(toml_get "$t" app-name) || app_args[allow_alpha_version]=false
	app_args[build_mode]=$(toml_get "$t" build-mode) || app_args[build_mode]=apk
	app_args[microg_patch]=$(toml_get "$t" microg-patch) || app_args[microg_patch]=""
	app_args[apkmirror_dlurl]=$(toml_get "$t" apkmirror-dlurl) && app_args[apkmirror_dlurl]=${app_args[apkmirror_dlurl]%/} || app_args[apkmirror_dlurl]=""
	app_args[arch]=$(toml_get "$t" arch) || app_args[arch]="all"
	app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || {
		app_name_l=${app_args[app_name],,}
		app_args[module_prop_name]=$([ "${app_args[arch]}" = "all" ] && echo "${app_name_l}-rv-jhc-magisk" || echo "${app_name_l}-${app_args[arch]}-rv-jhc-magisk")
	}
	if ! app_args[apkmirror_regex]=$(toml_get "$t" apkmirror-regex); then
		if [ "${app_args[arch]}" = "all" ]; then
			app_args[apkmirror_regex]="APK</span>[^@]*@\([^#]*\)"
		elif [ "${app_args[arch]}" = "arm64-v8a" ]; then
			app_args[apkmirror_regex]='arm64-v8a</div>[^@]*@\([^"]*\)'
		elif [ "${app_args[arch]}" = "arm-v7a" ]; then
			app_args[apkmirror_regex]='armeabi-v7a</div>[^@]*@\([^"]*\)'
		fi
	fi
	if [ "${app_args[apkmirror_dlurl]:-}" ] && [ "${app_args[apkmirror_regex]:-}" ]; then app_args[dl_from]=apkmirror; else app_args[dl_from]=uptodown; fi

	app_args[patcher_args]="$(join_args "${excluded_patches}" -e) $(join_args "${included_patches}" -i)"
	[ "$merge_integrations" = true ] && app_args[patcher_args]="${app_args[patcher_args]} -m ${RV_INTEGRATIONS_APK}"
	[ "$exclusive_patches" = true ] && app_args[patcher_args]="${app_args[patcher_args]} --exclusive"

	build_rv app_args &
	while [ "$(jobs -r | wc -l)" -ge "$PARALLEL_JOBS" ]; do sleep 3; done
done
wait

rm -rf temp/tmp.*

if [ "$BUILD_MINDETACH_MODULE" = true ]; then
	echo "Building mindetach module"
	cp -f $PKGS_LIST mindetach-magisk/mindetach/detach.txt
	cd mindetach-magisk/mindetach/
	zip -r ../../build/mindetach-"$(grep version= module.prop | cut -d= -f2)".zip .
	cd ../../
fi

youtube_mode=$(toml_get "YouTube" "build-mode") || youtube_mode="module"
music_arm_mode=$(toml_get "Music-arm" "build-mode") || music_arm_mode="module"
music_arm64_mode=$(toml_get "Music-arm64" "build-mode") || music_arm64_mode="module"
if [ "$youtube_mode" != module ] || [ "$music_arm_mode" != module ] || [ "$music_arm64_mode" != module ]; then
	log "\nInstall [Vanced Microg](https://github.com/TeamVanced/VancedMicroG/releases) to be able to use non-root YouTube or Music"
fi
log "\n[revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module)"

reset_template
echo "Done"
