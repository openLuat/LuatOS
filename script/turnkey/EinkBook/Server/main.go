package main

import (
	"bufio"
	"encoding/json"
	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
	"io"
	"io/ioutil"
	"os"
	"strconv"
	"strings"
)

func errHandle(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	fileList, err := ioutil.ReadDir("./books")
	errHandle(err)
	files := make(map[string]map[string]string)
	booksData := make(map[string][]string)
	for _, f := range fileList {
		if !f.IsDir() {
			file := make(map[string]string)
			file["size"] = strconv.FormatInt(f.Size(), 10)
			files[f.Name()] = file
		}
	}
	// 12列 * 11行
	for name, fileInfo := range files {
		bookName := "./books/" + name
		f, err := os.Open(bookName)
		errHandle(err)
		reader := bufio.NewReader(f)
		var lines []string
		var showList []string
		for {
			line, err := reader.ReadString('\n')
			if err != nil || io.EOF == err {
				break
			}
			line = strings.Trim(line, " ")
			// line = strings.ReplaceAll(line, "，", ",")
			// line = strings.ReplaceAll(line, "。", ".")
			line = strings.ReplaceAll(line, "“", "\"")
			line = strings.ReplaceAll(line, "”", "\"")
			line = strings.ReplaceAll(line, "？", "?")
			line = strings.ReplaceAll(line, "！", "!")
			line = strings.ReplaceAll(line, "：", ":")
			line = strings.ReplaceAll(line, "\r", "")
			line = strings.ReplaceAll(line, "\n", "")
			line = strings.ReplaceAll(line, "\t", "")
			line = strings.ReplaceAll(line, "\xe3\x80\x80", "")
			line = strings.ReplaceAll(line, "……", "...")
			line = strings.ReplaceAll(line, "（", "(")
			line = strings.ReplaceAll(line, "）", ")")
			line = strings.ReplaceAll(line, "》", ">")
			line = strings.ReplaceAll(line, "《", "<")
			line = strings.ReplaceAll(line, "—", "一")
			if line != "" {
				lines = append(lines, line)
			}
		}
		for _, line := range lines {
			runeLine := []rune(line)
			runeLine = append([]rune{' ', ' '}, runeLine...)
			runeLineLen := len(runeLine)
			if runeLineLen <= 13 {
				showList = append(showList, string(runeLine))
			} else {
				needSplitLen := runeLineLen - 13
				showList = append(showList, string(runeLine[:13]))
				num := needSplitLen / 12
				single := needSplitLen % 12
				runeLine = runeLine[13:]
				for i := 0; i < num; i++ {
					showList = append(showList, string(runeLine[12*i:12*i+12]))
				}
				if single != 0 {
					showList = append(showList, string(runeLine[12*num:needSplitLen]))
				}
			}
		}
		booksData[name] = showList
		pages := 0
		if len(showList)%11 == 0 {
			pages = len(showList) / 11
		} else {
			pages = len(showList)/11 + 1
		}
		fileInfo["pages"] = strconv.Itoa(pages)
	}
	s := g.Server()
	for name := range files {
		s.BindHandler("/"+name+"/{page}", func(r *ghttp.Request) {
			res := strings.Split(r.Request.URL.Path, "/")
			bookData := booksData[res[1]]
			page := r.Get("page").Int()
			var startIndex int = 11 * (page - 1)
			var list []string
			if startIndex >= len(bookData) {
				r.Response.Writef("%v\n", "已读完")
				return
			}
			for i := 0; i < 11; i++ {
				if startIndex+i >= len(bookData) {
					break
				}
				list = append(list, bookData[startIndex+i])
			}
			encodeJson, err := json.Marshal(list)
			errHandle(err)
			r.Response.Write(string(encodeJson))
		})
	}

	s.BindHandler("/getBooks", func(r *ghttp.Request) {
		encodeJson, err := json.Marshal(files)
		errHandle(err)
		r.Response.Write(string(encodeJson))
	})
	s.SetIndexFolder(true)
	s.SetServerRoot("./books")
	s.Run()
}
