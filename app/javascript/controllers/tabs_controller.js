import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values  = { active: String }

  connect() {
    const stored = localStorage.getItem("dashboard:tab")
    this.show(stored || this.activeValue || "crypto")
  }

  select(event) {
    const name = event.currentTarget.dataset.tabName
    this.show(name)
    localStorage.setItem("dashboard:tab", name)
  }

  show(name) {
    // Fallback ke panel yang ada — cegah blank page kalau tab tersimpan
    // (mis. "crypto") sudah tidak dirender lagi.
    const names = this.panelTargets.map(p => p.dataset.tabName)
    if (!names.includes(name)) name = names[0]

    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.tabName === name
      tab.classList.toggle("bg-gray-800",  isActive)
      tab.classList.toggle("text-white",   isActive)
      tab.classList.toggle("text-gray-500", !isActive)
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tabName !== name)
    })
  }
}
