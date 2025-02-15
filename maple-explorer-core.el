;;; maple-explorer-core.el ---  maple imenu configuration.	-*- lexical-binding: t -*-

;; Copyright (C) 2019 lin.jiang

;; Author: lin.jiang <mail@honmaple.com>
;; URL: https://github.com/honmaple/emacs-maple-explorer

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; maple explorer configuration.
;;

;;; Code:
(defgroup maple-explorer nil
  "Display explorer in window side."
  :group 'maple)

(defcustom maple-explorer-arrow '("▾" . "▸")
  "Display arrow when show or hide entry."
  :type 'cons
  :group 'maple-explorer)

(defcustom maple-explorer-indent 2
  "Display indent."
  :type 'integer
  :group 'maple-explorer)

(defface maple-explorer-face
  '((t (:inherit font-lock-type-face)))
  "Default face for maple-explorer.")

(defface maple-explorer-mark-face
  '((t (:inherit font-lock-constant-face)))
  "Mark face for maple-explorer.")

(defface maple-explorer-item-face
  '((t (:inherit font-lock-variable-name-face)))
  "Default item face for maple-explorer.")

(defvar-local maple-explorer-opened-list nil)
(defvar-local maple-explorer-closed-list nil)
(defvar-local maple-explorer-name-function nil)

(defun maple-explorer--is-open(info)
  "Check INFO is open, nil mean open."
  (let ((status (plist-get info :status))
        (value  (plist-get info :value)))
    (cond ((and value (member value maple-explorer-opened-list)) t)
          ((and value (member value maple-explorer-closed-list)) nil)
          ((not status) t)
          ((eq status 'open) t))))

(defun maple-explorer--set-open(info &optional close)
  "Set INFO when OPEN or CLOSE."
  (let ((value (plist-get info :value)))
    (if close (progn
                (plist-put info :status 'close)
                (add-to-list 'maple-explorer-closed-list value)
                (setq maple-explorer-opened-list (delete value maple-explorer-opened-list)))
      (plist-put info :status 'open)
      (add-to-list 'maple-explorer-opened-list value)
      (setq maple-explorer-closed-list (delete value maple-explorer-closed-list)))))

(defun maple-explorer-table-merge(key value table face)
  "Set KEY VALUE TABLE FACE."
  (unless (listp key) (setq key (list key)))
  (let* ((x (car key))
         (v (or (gethash x table) (list))))
    (cl-loop for n in (reverse (cdr key))
             do (setq value (list :name n :face face :children (list value) :click 'maple-explorer-fold)))
    (let* ((k (plist-get value :name))
           (m (cl-loop for n in v when (string= (plist-get n :name) k) return n)))
      (if m (plist-put m :children (append (plist-get m :children) (plist-get value :children)))
        (setq v (append v (list value)))))
    (puthash x v table)))

(defun maple-explorer-list(lists &optional face info-function filter-function group-function)
  "LISTS &OPTIONAL FACE INFO-FUNCTION FILTER-FUNCTION GROUP-FUNCTION."
  (let ((table   (make-hash-table :test 'equal)) children)
    (dolist (child lists)
      (when (or (not filter-function) (funcall filter-function child))
        (let ((group (when group-function (funcall group-function child)))
              (info  (if info-function (funcall info-function child) child)))
          (if group (maple-explorer-table-merge group info table face) (push info children)))))
    (maphash
     (lambda(key value)
       (setq children (append children (list (list :status 'close :name key :face face :children value :click 'maple-explorer-fold)))))
     table)
    (list :children children)))

(defmacro maple-explorer--with-buffer (name &rest body)
  "Execute BODY with buffer NAME."
  (declare (indent defun))
  `(with-current-buffer (get-buffer-create ,name)
     (let ((inhibit-read-only t)) (save-excursion ,@body))))

(defmacro maple-explorer--with-window (name &rest body)
  "Execute BODY with window NAME."
  (declare (indent defun))
  `(let ((window (get-buffer-window ,name t)))
     (when window (with-selected-window window ,@body))))

(defmacro maple-explorer-with(&rest body)
  "Excute BODY."
  (declare (indent defun))
  `(let* ((button (button-at (point)))
          (info   (button-get button 'maple-explorer)))
     (unless (or button info) (error "No item found at point")) ,@body))

(defun maple-explorer--indent()
  "Get current line indent."
  (let ((text (thing-at-point 'line t)))
    (- (string-width text) (string-width (string-trim-left text)))))

(defun maple-explorer--point()
  "Get next point."
  (let* ((level (maple-explorer--indent))
         (point (line-end-position))
         stop)
    (save-excursion
      (while (not stop)
        (forward-line 1)
        (if (and (> (maple-explorer--indent) level) (< point (point-max)))
            (setq point (line-end-position)) (setq stop t))))
    point))

(defun maple-explorer-name(info)
  "Default name format of INFO."
  (if maple-explorer-name-function
      (funcall maple-explorer-name-function info)
    (let ((isroot   (plist-get info :isroot))
          (name     (plist-get info :name))
          (children (plist-get info :children)))
      (if (and (not isroot) children)
          (format
           "%s %s"
           (if (maple-explorer--is-open info)
               (car maple-explorer-arrow) (cdr maple-explorer-arrow))
           name)
        name))))

(defun maple-explorer-insert(info &optional indent)
  "Insert INFO &OPTIONAL INDENT."
  (let ((name     (plist-get info :name))
        (face     (plist-get info :face))
        (click    (plist-get info :click))
        (children (plist-get info :children))
        (indent   (or indent 0)))
    (when name
      (insert-button
       (format "%s%s" (make-string indent ?\s) (maple-explorer-name info))
       'action `(lambda (_) (interactive "e") (call-interactively ',click))
       'follow-link t
       'maple-explorer info
       'face (or face 'maple-explorer-item-face))
      (insert "\n")
      (setq indent (+ indent maple-explorer-indent)))
    (when (and (maple-explorer--is-open info) children)
      (when (functionp children)
        (setq children (funcall children)))
      (dolist (child children) (maple-explorer-insert child indent)))))

(defun maple-explorer--fold(&optional status)
  "Turn on or off fold with STATUS at point."
  (maple-explorer-with
    (let* ((indent (maple-explorer--indent))
           (inhibit-read-only t))
      (maple-explorer--set-open info status)
      (save-excursion
        (delete-region
         (line-beginning-position)
         (min (point-max) (+ (maple-explorer--point) 1)))
        (maple-explorer-insert info (max 0 (- indent (or (plist-get info :indent) 0))))))))

(defun maple-explorer-fold-on()
  "Turn on fold at point."
  (interactive)
  (maple-explorer--fold))

(defun maple-explorer-fold-off()
  "Turn off fold at point."
  (interactive)
  (maple-explorer--fold t))

(defun maple-explorer-fold()
  "Toggle fold at point."
  (interactive)
  (maple-explorer-with
    (call-interactively
     (if (maple-explorer--is-open info)
         'maple-explorer-fold-off 'maple-explorer-fold-on))))

(defun maple-explorer-filter-list(&optional filter key)
  "Get KEY list with FILTER function."
  (let (filter-list button info)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (setq button (button-at (point)))
        (setq info   (button-get button 'maple-explorer))
        (when (and filter (funcall filter button info))
          (push (if key (plist-get info key) info) filter-list))
        (forward-line 1)))
    filter-list))

(defun maple-explorer-mark-list()
  "Get marked list."
  (maple-explorer-filter-list
   (lambda(button _info) (button-get button 'maple-explorer-mark))))

(defun maple-explorer-mark-or-unmark()
  "Mark or unmark the POINT value."
  (interactive)
  (maple-explorer-with
    (call-interactively
     (if (button-get button 'maple-explorer-mark)
         'maple-explorer-unmark 'maple-explorer-mark))))

(defun maple-explorer-mark()
  "Mark the POINT value."
  (interactive)
  (maple-explorer-with
    (button-put button 'face 'maple-explorer-mark-face)
    (button-put button 'maple-explorer-mark t)
    (forward-line)))

(defun maple-explorer-unmark()
  "Mark the POINT value."
  (interactive)
  (maple-explorer-with
    (button-put button 'face (or (plist-get info :face) 'maple-explorer-item-face))
    (button-put button 'maple-explorer-mark nil)
    (forward-line)))

(defun maple-explorer-unmark-all()
  "UnMark all value."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp)) (maple-explorer-unmark) (forward-line 1))))

(defmacro maple-explorer-define(name &rest body)
  "Define new explorer NAME &REST BODY."
  (declare (indent 1) (doc-string 2))
  (let* ((prefix (format "maple-explorer-%s" name))
         (togg-function (intern prefix))
         (show-function (intern (format "%s-show" prefix)))
         (hide-function (intern (format "%s-hide" prefix)))
         (mode-function (intern (format "%s-mode" prefix)))
         (list-function (intern (format "%s-list" prefix)))
         (window-function (intern (format "%s-window" prefix)))
         (resize-function (intern (format "%s-window-resize" prefix)))
         (display-function (intern (format "%s-display" prefix)))
         (refresh-function (intern (format "%s-refresh" prefix)))
         (right-click-function (intern (format "%s-right-click" prefix)))

         (init-hook (intern (format "%s-init-hook" prefix)))
         (finish-hook (intern (format "%s-finish-hook" prefix)))

         (mode-map (intern (format "%s-mode-map" prefix)))
         (name-func (intern (format "%s-name-function" prefix)))
         (group-func (intern (format "%s-group-function" prefix)))
         (filter-func (intern (format "%s-filter-function" prefix)))
         (right-menu-func (intern (format "%s-right-menu-function" prefix)))
         (auto-resize (intern (format "%s-autoresize" prefix)))
         (buffer-name (intern (format "%s-buffer" prefix)))
         (buffer-width (intern (format "%s-width" prefix)))
         (display-alist (intern (format "%s-display-alist" prefix))))
    `(progn
       (defcustom ,buffer-name ,(format "*%s*" prefix)
         "Buffer name."
         :type 'string
         :group ',togg-function)

       (defcustom ,buffer-width '(40 . 50)
         "Window's length (min . max)."
         :type 'cons
         :group ',togg-function)

       (defcustom ,display-alist '((side . left) (slot . -1))
         "Window display alist."
         :type '(cons)
         :group 'togg-function)

       (defcustom ,auto-resize t
         "Whether auto resize window when item's length is long."
         :type 'boolean
         :group ',togg-function)

       (defcustom ,name-func nil
         "Explorer name format function."
         :type 'function
         :group ',togg-function)

       (defcustom ,filter-func nil
         "Explorer filter function."
         :type 'function
         :group ',togg-function)

       (defcustom ,group-func nil
         "Explorer group function."
         :type 'function
         :group ',togg-function)

       (defcustom ,right-menu-func nil
         "Explorer right menu function."
         :type 'function
         :group ',togg-function)

       (defcustom ,init-hook nil
         "Explorer init hook."
         :type 'list
         :group ',togg-function)

       (defcustom ,finish-hook nil
         "Explorer finish hook."
         :type 'list
         :group ',togg-function)

       (defun ,window-function()
         "Get current explorer window."
         (get-buffer-window ,buffer-name t))

       (defun ,resize-function()
         "Resize explorer window."
         (maple-explorer--with-window ,buffer-name
           (setq window-size-fixed nil)
           (let* ((min-width (max (car ,buffer-width) window-min-width))
                  (max-width (cdr ,buffer-width)))
             (when (and ,auto-resize (not (= min-width max-width)))
               (let ((fit-window-to-buffer-horizontally t)) (fit-window-to-buffer)))
             (if (> (window-width) max-width)
                 (shrink-window-horizontally (- (window-width) max-width))
               (when (< (window-width) min-width)
                 (enlarge-window-horizontally (- min-width (window-width))))))
           (setq window-size-fixed 'width)))

       (defun ,display-function(buffer _alist)
         "Explorer window display function with BUFFER _ALIST."
         (display-buffer-in-side-window buffer ,display-alist))

       (defun ,show-function()
         "Show explorer window."
         (interactive)
         (run-hooks ',init-hook)
         (,refresh-function t))

       (defun ,hide-function()
         "Hide explorer window."
         (interactive)
         (let ((window (,window-function)))
           (when window
             (delete-window window)
             (kill-buffer ,buffer-name)))
         (setq maple-explorer-opened-list nil)
         (setq maple-explorer-closed-list nil)
         (run-hooks ',finish-hook))

       (defun ,togg-function()
         "Toggle explorer window."
         (interactive)
         (if (,window-function) (,hide-function) (,show-function)))

       (defun ,refresh-function(&optional first)
         "Refresh explorer buffer when FIRST enable mode."
         (interactive)
         (let* ((maple-explorer-name-function ,name-func)
                (items  (,list-function t))
                (buffer ,buffer-name))
           (when (or (not items) (not (plist-get items :children)))
             (error "There is no result"))
           (maple-explorer--with-buffer buffer
             (erase-buffer)
             (maple-explorer-insert items)
             (unless (zerop (buffer-size))
               (delete-region (- (point-max) 1) (point-max)))
             (when first
               (select-window (display-buffer buffer '(,display-function)))
               (,mode-function)))
           (,resize-function)))

       (defun ,right-click-function(event)
         "Right click EVENT."
         (interactive "e")
         (unless ,right-menu-func (error "No right menu defined!"))
         (let* ((point  (event-start event))
                (menu   (funcall ,right-menu-func))
                (choice (x-popup-menu event menu)))
           (when choice
             (with-selected-window (posn-window point)
               (goto-char (posn-point point))
               (call-interactively (lookup-key menu (apply 'vector choice)))))))

       (defvar ,mode-map
         (let ((map (make-sparse-keymap)))
           (define-key map (kbd "q") ',hide-function)
           (define-key map (kbd "r") ',refresh-function)
           map)
         ,(format "%s-mode-map keymap." prefix))

       (define-derived-mode ,mode-function special-mode ,(capitalize (format "%s Explorer" name))
         ,(format "%s-mode." prefix)
         (setq indent-tabs-mode nil
               buffer-read-only t
               truncate-lines -1
               cursor-type nil
               cursor-in-non-selected-windows nil)

         (setq maple-explorer-name-function ,name-func)

         (when (bound-and-true-p evil-mode)
           (evil-make-overriding-map ,mode-map 'normal)))

       ,@body)))

(provide 'maple-explorer-core)
;;; maple-explorer-core.el ends here
