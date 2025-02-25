#!/usr/bin/env emacs --script

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; Comment/uncomment this line to enable MELPA Stable if desired.  See `package-archive-priorities`
;; and `package-pinned-packages`. Most users will not need or want to do this.
;;(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/") t)
(package-initialize)

;; (package-refresh-contents)
;; Install and load different language modes
(setq package-selected-packages
      '(rust-mode
        php-mode
        python-mode

        htmlize
        color-theme-sanityinc-tomorrow
        ))
(package-install-selected-packages t)

(require 'rust-mode)
(require 'python-mode)
(require 'php-mode)


(require 'htmlize)
(require 'color-theme-sanityinc-tomorrow)
(load-theme 'sanityinc-tomorrow-night t)

(require 'ox-publish)
(load "~/blog/ox-rss.el")

(defun get-content (filePath)
  "Returns the content of the file pointed to by filePath"
  (with-temp-buffer
    (insert-file-contents filePath)
    (buffer-string)))

(defun c3lphie/org-get-keywords (filePath)
  (with-temp-buffer
                   (insert-file-contents filePath)
                   (org-mode)
                   (org-element-map (org-element-parse-buffer 'element) 'keyword
                     (lambda (keyword) (cons (org-element-property :key keyword)
                                             (org-element-property :value keyword))))))

(defun c3lphie/org-pages-publish (plist filename pub-dir)
  (if (equal "sitemap.org" (file-name-directory filename))
      (org-rss-publish-to-rss plist filename pub-dir)
    (org-html-publish-to-html plist filename pub-dir)))

(defun c3lphie/org-get-keyword (keyword filePath)
  (cdr (assoc keyword (c3lphie/org-get-keywords filePath))))

(defun c3lphie/org-get-summary (entry)
  (c3lphie/org-get-keyword "SUMMARY" entry))

(defun c3lphie/html-header (arg)
  "Returns the content of the static html header"
  (get-content "~/blog/static_html/html_head.html"))

(defun c3lphie/html-preamble (arg)
  "Returns the content of the static html preamble"
  (get-content "~/blog/static_html/html_preamble.html"))

(defun c3lphie/html-postamble (arg)
  "Returns the content of the static html postamble"
  (get-content "~/blog/static_html/html_postamble.html"))

(defun c3lphie/org-rss-publish-to-rss (plist filename pub-dir)
  (if (equal "rss.org" (file-name-nondirectory filename))
      (org-rss-publish-to-rss plist filename pub-dir)))

(defun c3lphie/format-rss-feed (title list)
  (concat "#+TITLE: " title "\n"
          (org-list-to-subtree list)))

(defun c3lphie/format-rss-feed-entry (entry syle project)
  (cond ((not (directory-name-p entry))
         (let* ((file (org-publish--expand-file-name entry project))
                (title (org-publish-find-title entry project))
                (date (format-time-string "%d-%m-%Y"
                                          (org-publish-find-date entry project)))
                (link (concat (file-name-sans-extension entry) ".html")))
           (with-temp-buffer
             (insert (format "%s\n" title))
             (org-set-property "PUBDATE" date)
             (org-set-property "RSS_PERMALINK" link)
             (insert-file-contents file)
             (buffer-string))))
        ((eq style 'tree)
         (file-name-nondirectory (directory-file-name entry)))
        (t entry)))

(defun c3lphie/org-sitemap-function (title list)
  (concat "#+TITLE: " title "\n"
          "#+setupfile: ../templates/level-0.org\n"
          "#+begin_export html
<style>
  header {
  text-align: center;
  positon: fixed;
  margin-top: 0px;
  padding: 1px;
  background-color: var(--bg-alt-color);
  }
  li{
  max-width: 95%;
  padding-left: 2.5%;
  }
  #avatar {
    position: absolute;
    width: 72.5px;
    top: 5px;
    left: 20%;
  }
  @media (pointer:coarse){
    #avatar {
    display: none;
    }
  }
</style>
<a href='/'><img src='static/c3lphie.png' id='avatar'></img></a>
#+end_export\n\n"
          (org-list-to-org list)))

(defun c3lphie/org-sitemap-entry-format (entry style project)
  "Format ENTRY in org-publish PROJECT Sitemap"
  (let ((filename (org-publish-find-title entry project)))
    (if (= (length filename) 0)
        (format "*%s*" entry)
      (format (concat "{{{timestamp(%s)}}} [[file:%s][%s]]"
                      "\n%s")
              (format-time-string "%d-%m-%Y"
                                  (org-publish-find-date entry project))
              entry
              filename
              (c3lphie/org-get-summary (format "posts/%s" entry))))))

(setq org-export-global-macros
      '(("timestamp" . "@@html:<span class=\"timestamp\">[$1]</span>@@")))

(setq org-export-with-todo-keywords nil
      org-html-htmlize-output-type 'css)

(setq htmlize-untabify nil)
;; Project alist
(setq org-publish-project-alist
      '(("blog-posts"
         :base-directory "~/blog/posts/"
         :base-extension "org"
         :publishing-directory "~/blog"
         :exclude "*.org~\\|*.draft.org\\|rss.org"
         :auto-sitemap t
         :sitemap-filename "~/blog/pages/sitemap.org"
         :sitemap-sort-files anti-chronologically
         :sitemap-date-format "Published: %d-%m-%Y"
         :sitemap-format-entry c3lphie/org-sitemap-entry-format
         :sitemap-title "All posts"
         :preserve-breaks t
         :sitemap-function c3lphie/org-sitemap-function
         :headline-levels 5
         :section-numbers t
         :with-toc t
         :recursive t
         :publishing-function org-html-publish-to-html
         :html-preamble c3lphie/html-preamble
         :html-postamble c3lphie/html-postamble)
        ("blog-rss"
         :base-directory "~/blog/posts"
         :base-extension "org"
         :publishing-directory "~/blog"
         :rss-extension "xml"
         :exclude ".*"
         :include ("../pages/sitemap.org")
         :publishing-function (org-rss-publish-to-rss)
         )
        ("blog-pages"
         :base-directory "~/blog/pages/"
         :base-extension "org"
         :publishing-directory "~/blog"
         :recursive t
         :preserve-breaks t
         :publishing-function c3lphie/org-pages-publish
         :org-html-preamble nil
         :html-postamble c3lphie/html-postamble)
        ("blog-assets"
         :base-directory "~/blog/posts/assets/"
         :base-extension "jpg\\|png\\|gif"
         :publishing-directory "~/blog/assets/"
         :recursive t
         :publishing-function org-publish-attachment)
        ("blog"
         :components ("blog-posts"
                      "blog-rss"
                      "blog-pages"
                      "blog-assets"))))

(org-publish "blog" t)
