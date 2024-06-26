﻿; (C) Copyright 2021, Bartlomiej Uliasz
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
; http://www.apache.org/licenses/LICENSE-2.0
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; This code is based on the original Makefile from tesstrain repository

#include _helper.ahk

SUPPORTED_IMAGE_FILES := [".bin.png", ".nrm.png", ".png", ".tif", ".bmp"]

PYTHON_EXE := "python"

BIN_DIR := "C:\Program Files\Tesseract-OCR"
BINARIES := Map(
	"tesseract", 			BIN_DIR "\tesseract.exe",
	"combine_tessdata", 	BIN_DIR "\combine_tessdata.exe",
	"unicharset_extractor", BIN_DIR "\unicharset_extractor.exe",
	"merge_unicharsets", 	BIN_DIR "\merge_unicharsets.exe",
	"lstmtraining", 		BIN_DIR "\lstmtraining.exe",
	"combine_lang_model", 	BIN_DIR "\combine_lang_model.exe"
)

; Path to the .traineddata directory with traineddata suitable for training
; (for example from tesseract-ocr\tessdata_best). Default: BIN_DIR "\tessdata"
TESSDATA :=  BIN_DIR "\tessdata"

; Name of the model to be built. Default: "foo"
MODEL_NAME := "foo"

; Data directory for output files, proto model, start model, etc. Default: "data"
DATA_DIR :=  A_ScriptDir "\data"

; Output directory for generated files. Default: DATA_DIR "\" MODEL_NAME
OUTPUT_DIR := DATA_DIR "\" MODEL_NAME

; Ground truth directory. Default: OUTPUT_DIR "-ground-truth"
GROUND_TRUTH_DIR := A_ScriptDir "\ocrd-testset"

; Optional Wordlist file for Dictionary dawg. Example: OUTPUT_DIR "\" MODEL_NAME ".wordlist". Default: none
WORDLIST_FILE := ""

; Optional Numbers file for number patterns dawg. Example: OUTPUT_DIR "\" MODEL_NAME ".numbers". Default: none
NUMBERS_FILE := ""

; Optional Punc file for Punctuation dawg. Example: OUTPUT_DIR "\" MODEL_NAME ".punc". Default: none
PUNC_FILE := ""

; Name of the model to continue from. Default: ''
START_MODEL := ""

LAST_CHECKPOINT := OUTPUT_DIR "\checkpoints\" MODEL_NAME "_checkpoint"

; Name of the proto model. Default: OUTPUT_DIR "\" MODEL_NAME ".traineddata"
PROTO_MODEL := OUTPUT_DIR "\" MODEL_NAME ".traineddata"

EPOCHS := ""

; Max iterations. Default: 10000 / -EPOCHS
; If EPOCHS is given, it is used to set MAX_ITERATIONS.
if (EPOCHS == "") {
	MAX_ITERATIONS := 10000
} else {
	MAX_ITERATIONS := -EPOCHS
}

; Debug Interval. Default:  0
DEBUG_INTERVAL := 0

; Learning rate. Default: 0.0001 / 0.002
if (START_MODEL != "") {
	LEARNING_RATE := 0.0001
} else {
	LEARNING_RATE := 0.002
}

; Network specification. Default: [1,36,0,1 Ct3,3,16 Mp3,3 Lfys48 Lfx96 Lrx96 Lfx192 O1c###]
NET_SPEC := "[1,36,0,1 Ct3,3,16 Mp3,3 Lfys48 Lfx96 Lrx96 Lfx192 O1c###]"

; Language Type - Indic, RTL or blank. Default: ''
LANG_TYPE := "Default"

; Normalization mode - 2, 1 - for unicharset_extractor and Pass through Recoder for combine_lang_model
if (LANG_TYPE == "Indic") {
	NORM_MODE := 2
	PASS_THROUGH_RECORDER := true
	LANG_IS_RTL := false
	GENERATE_BOX_SCRIPT := "generate_wordstr_box.py"
}
else if (LANG_TYPE == "RTL") {
	NORM_MODE := 3
	PASS_THROUGH_RECORDER := true
	LANG_IS_RTL := true
	GENERATE_BOX_SCRIPT := "generate_wordstr_box.py"
}
else {
	NORM_MODE := 2		; 1 might be better for Latin characters
	PASS_THROUGH_RECORDER := false
	LANG_IS_RTL := false
	GENERATE_BOX_SCRIPT := "generate_line_box.py"
}

; Page segmentation mode. Default: 13
PSM := 13

; Random seed for shuffling of the training data. Default: 0
RANDOM_SEED := 0

; Ratio of train / eval training data. Default: 0.90
RATIO_TRAIN := round(0.90, 2)

; Default Target Error Rate. Default: 0.01
TARGET_ERROR_RATE := 0.01

; Default directory for TessTrain .py scripts
TESSTRAIN_DIR := A_ScriptDir

DEFAULT_STATUS_FUNCTION := (statusMessage) => TemporaryTooltip(statusMessage, 2)
StatusUpdate := DEFAULT_STATUS_FUNCTION

; Make sure that extensions are sorted starting from the longest, to avoid situations where for 'name.bin.png' produced txt file name would be 'name.bin.gt.txt' instead of 'name.gt.txt'.
SUPPORTED_IMAGE_FILES := ArraySort(SUPPORTED_IMAGE_FILES, StrLengthCmp)
StrLengthCmp(str1, str2) {
	return StrLen(str2)-StrLen(str1)
}

; If LAST_CHECKPOINT already exists it will just convert it to .traineddata file
StartTraining() {
	if (!FileExist(LAST_CHECKPOINT)) {
		if (!TrainAndProduceCheckpoints()) {
			StatusUpdate("Training error")
			return false
		}
	}
	if (BEEP_END_TRAINING) {
		SoundBeep 500, 150
		SoundBeep 800, 300
	}
	Checkpoint2Traineddata(LAST_CHECKPOINT, DATA_DIR "\" MODEL_NAME ".traineddata", false)
	StatusUpdate("Training finished")
	return true
}

MultipleCheckpointToTraineddata(checkpointFileList, isFast) {
	bestOrFast := isFast ? "fast" : "best"
	StatusUpdate("Creating '_" bestOrFast ".traineddata' files from selected checkpoint files")

	targetDir := OUTPUT_DIR "\traineddata_" bestOrFast
	DirCreate(targetDir)
	for (checkpointFile in checkpointFileList) {
		outputTraineddataFile := targetDir "\" StrCutEnd(FileGetName(checkpointFile), StrLen("checkpoint")) "traineddata"
		Checkpoint2Traineddata(checkpointFile, outputTrainedDataFile, isFast)
	}
	return outputTrainedDataFile
}

Checkpoint2Traineddata(inputCheckpointFile, outputTrainedDataFile, isConvertToInt) {
	ExecuteCommand(
		"`"" BINARIES["lstmtraining"] "`""
			. " --stop_training"
			. " --continue_from `"" inputCheckpointFile "`""
			. " --traineddata `"" PROTO_MODEL "`""
			. (isConvertToInt ? " --convert_to_int" : "")
			. " --model_output `"" outputTraineddataFile "`""
	)
}

TrainAndProduceCheckpoints() {
	GenerateUnicharset()
	GenerateTrainAndEvalLists()
	GenerateProtoModel()	; uses generated Unicharset

	StatusUpdate("Executing the training")

	DirCreate(OUTPUT_DIR "\checkpoints")
	SetWorkingDir OUTPUT_DIR

	DisableSystemStandby(true)	; prevent System standby during training
	if (START_MODEL != "") {
		ExecuteCommand(
			"`"" BINARIES["lstmtraining"] "`""
				. " --debug_interval " DEBUG_INTERVAL
				. " --traineddata `"" PROTO_MODEL "`""
				. " --old_traineddata `"" TESSDATA "\" START_MODEL ".traineddata`""
				. " --continue_from `"" DATA_DIR "\" START_MODEL "\" MODEL_NAME ".lstm`""
				. " --learning_rate " LEARNING_RATE
				. " --model_output `"" OUTPUT_DIR "\checkpoints\" MODEL_NAME "`""
				. " --train_listfile `"" OUTPUT_DIR "\list.train`""
				. " --eval_listfile `"" OUTPUT_DIR "\list.eval`""
				. " --max_iterations " MAX_ITERATIONS
				. " --target_error_rate " TARGET_ERROR_RATE,
			3)
	}
	else {
		netSpec := StrReplace(NET_SPEC, "c###", "c" FileGetFirstLine(OUTPUT_DIR "\unicharset"))
		ExecuteCommand(
			"`"" BINARIES["lstmtraining"] "`""
				. " --debug_interval " DEBUG_INTERVAL
				. " --traineddata `"" PROTO_MODEL "`""
				. " --learning_rate " LEARNING_RATE
				. " --net_spec `"" netSpec "`""
				. " --model_output `"" OUTPUT_DIR "\checkpoints\" MODEL_NAME "`""
				. " --train_listfile `"" OUTPUT_DIR "\list.train`""
				. " --eval_listfile `"" OUTPUT_DIR "\list.eval`""
				. " --max_iterations " MAX_ITERATIONS
				. " --target_error_rate " TARGET_ERROR_RATE,
			3)
	}
	DisableSystemStandby(false)

	SetWorkingDir(A_ScriptDir)
	return true
}

; Create unicharset
GenerateUnicharset() {
	StatusUpdate("Creating unicharset")
	DirCreate(OUTPUT_DIR)
	target := OUTPUT_DIR "\unicharset"
	if (START_MODEL != "") {
		DirCreate(DATA_DIR "\" START_MODEL)
		ExecuteCommand(
			"`"" BINARIES["combine_tessdata"] "`""
				. " -u `"" TESSDATA "\" START_MODEL ".traineddata`""
				. " `"" DATA_DIR "\" START_MODEL "\" MODEL_NAME "`""
		)
		ExecuteCommand(
			"`"" BINARIES["unicharset_extractor"] "`""
				. " --output_unicharset `"" OUTPUT_DIR "\my.unicharset`""
				. " --norm_mode " NORM_MODE
				. " `"" CreateCombinedGtTxtFile() "`""
		)
		ExecuteCommand(
			"`"" BINARIES["merge_unicharsets"] "`""
				. " `"" DATA_DIR "\" START_MODEL "\" MODEL_NAME ".lstm-unicharset`""
				. " `"" OUTPUT_DIR "\my.unicharset`""
				. " `"" target "`"")
	}
	else {
		DirCreate(OUTPUT_DIR)
		ExecuteCommand(
			"`"" BINARIES["unicharset_extractor"] "`""
				. " --output_unicharset `"" target "`""
				. " --norm_mode " NORM_MODE
				. " `"" CreateCombinedGtTxtFile() "`""
		)
	}
}

CheckLineImageExistence(name) {
	imageFile := ""

	for (extension in SUPPORTED_IMAGE_FILES) {
		if FileExist(name extension) {
			return true
		}
	}

	if (YesNoConfirmation("Corresponding Line Image file not found for '" name ".gt.txt'. Do you want to delete it?")) {
		FileDelete(name ".gt.txt")
	}
	return false
}

CreateCombinedGtTxtFile() {
	gtTxtList := FindAllFiles(GROUND_TRUTH_DIR "\*.gt.txt")
	allGt := OUTPUT_DIR "\all-gt"
	for (gtTxtFile in gtTxtList) {
		if (!CheckLineImageExistence(StrCutEnd(gtTxtFile, StrLen(".gt.txt")))) {
			continue
		}
		text := FileRead(gtTxtFile)
		FileAppend(text, allGt)
	}
	return allGt
}

; Create lists of lstmf filenames for training and eval
GenerateTrainAndEvalLists() {
	DirCreate(OUTPUT_DIR)

	allLstmf := GenerateAllLstmfFiles()
	total := allLstmf.Length

	train := Floor(total * RATIO_TRAIN)
	if (train < 1) {
		throw Error("Error: Not enough Ground Truth for training. Found " total " '.gt.txt' files with train/eval ratio " RATIO_TRAIN ".")
	}

	eval := total - train
	if (eval < 1) {
		throw Error("Error: Not enough Ground Truth for evaluation. Found " total " '.gt.txt' files with train/eval ratio " RATIO_TRAIN ".")
	}

	StatusUpdate("Creating 'list.train' and 'list.eval' of .lstmf files")
	
	trainList := ArrayHead(allLstmf, train)
	FileSave(OUTPUT_DIR "\list.train", ArrayToString(trainList, "`n") "`n")

	evalList := ArrayTail(allLstmf, eval)
	FileSave(OUTPUT_DIR "\list.eval", ArrayToString(evalList, "`n") "`n")
}

GenerateAllLstmfFiles() {
	StatusUpdate("Generating .box and .lstmf files")
	DirCreate(OUTPUT_DIR)

	gtTxtList := FindAllFiles(GROUND_TRUTH_DIR "\*.gt.txt")
	nameList := ArrayTransform(gtTxtList, StrCutEnd, StrLen(".gt.txt"))

	ArrayForEach(nameList, GenerateBoxAndLstmfFile)
	
	lstmfFilesList := FindAllFiles(GROUND_TRUTH_DIR "\*.lstmf")

	FileSave(OUTPUT_DIR "\all-lstmf", ArrayToString(lstmfFilesList, "`n") "`n")

	ExecuteCommand(PYTHON_EXE " `"" TESSTRAIN_DIR "\shuffle.py`" " RANDOM_SEED " < `"" OUTPUT_DIR "\all-lstmf`" > `"" OUTPUT_DIR "\all-lstmf.shuffled`"", 2)
	lstmfList := GetNonEmptyLines(OUTPUT_DIR "\all-lstmf.shuffled")

	return lstmfList
}

GenerateBoxAndLstmfFile(fileName) {
	imageFile := ""

	for (extension in SUPPORTED_IMAGE_FILES) {
		if FileExist(fileName extension) {
			GenerateBoxFileFromImage(fileName, extension)
			imageFile := fileName extension
			break
		}
	}

	if (FileExist(fileName ".lstmf") && !IsFileNewer(fileName ".box", fileName ".lstmf")) {
		return
	}

	ExecuteCommand("`"" BINARIES["tesseract"] "`" `"" imageFile "`" `"" fileName "`" --psm " PSM " lstm.train")
}

GenerateBoxFileFromImage(fullImagePathWithoutExtension, imageExtension) {
	boxFileFullPath 	:= fullImagePathWithoutExtension ".box"
	imageFileFullPath 	:= fullImagePathWithoutExtension imageExtension
	gtTxtFileFullPath 	:= fullImagePathWithoutExtension ".gt.txt"
	if (!FileExist(boxFileFullPath) || FileGetSize(boxFileFullPath) == 0
		|| IsFileNewer(imageFileFullPath, boxFileFullPath)
		|| IsFileNewer(gtTxtFileFullPath, boxFileFullPath)
	) {
		ExecuteCommand("set PYTHONIOENCODING=utf-8 && " PYTHON_EXE " `"" TESSTRAIN_DIR "\" GENERATE_BOX_SCRIPT "`" -i `"" imageFileFullPath "`" -t `"" gtTxtFileFullPath "`" > `"" boxFileFullPath "`"", 2)
	}
}

GenerateProtoModel() {
	StatusUpdate("Building the proto model for the new model")

	DownloadRadicalStrokeTxtIfNecessary()

	command := "`"" BINARIES["combine_lang_model"] "`""
		. " --input_unicharset `"" OUTPUT_DIR "\unicharset`""
		. " --script_dir `"" DATA_DIR "`""
		. (NUMBERS_FILE ? (" --numbers `"" NUMBERS_FILE) "`"" : "")
		. (PUNC_FILE ? " --puncs `"" PUNC_FILE "`"" : "")
		. (WORDLIST_FILE ? " --words `"" WORDLIST_FILE "`"" : "")
		. " --output_dir `"" DATA_DIR "`""
		. (PASS_THROUGH_RECORDER ? " --pass_through_recoder" : "")
		. (LANG_IS_RTL ? " --lang_is_rtl" : "")
		. " --lang `"" MODEL_NAME "`""

	ExecuteCommand(command)
}

DownloadRadicalStrokeTxtIfNecessary() {
	if (!FileExist(DATA_DIR "\radical-stroke.txt")) {
		StatusUpdate("Downloading 'radical-stroke.txt' file")
		Download("https://github.com/tesseract-ocr/langdata_lstm/raw/main/radical-stroke.txt", DATA_DIR "\radical-stroke.txt")
	}
}

; Clean generated .box files
DeleteBoxFiles() {
	FileDelete(GROUND_TRUTH_DIR "\*.box")
}

; Clean generated .lstmf files
DeleteLstmfFiles() {
	FileDelete(GROUND_TRUTH_DIR "\*.lstmf")
}

; Clean generated output files
DeleteModelData() {
	SetWorkingDir(A_ScriptDir)
	if (DirExist(OUTPUT_DIR)) {
		loop {
			try {
				DirDelete(OUTPUT_DIR, true)
				break
			} catch Error as e {
				if (!YesNoConfirmation("Could not delete '" OUTPUT_DIR "'. Do you want to try removing it again?")) {
					throw Error("Output directory could not be removed")
				}
			}
		}
	}
}
