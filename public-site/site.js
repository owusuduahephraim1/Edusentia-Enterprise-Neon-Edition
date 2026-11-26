"use strict";
(() => {
  const menuButton = document.querySelector(".menu-button");
  const nav = document.getElementById("main-menu");
  if(menuButton && nav){
    const close = () => {menuButton.setAttribute("aria-expanded","false");menuButton.setAttribute("aria-label","Open menu");nav.classList.remove("open");};
    menuButton.addEventListener("click",() => {
      const expanded=menuButton.getAttribute("aria-expanded")==="true";
      menuButton.setAttribute("aria-expanded",String(!expanded));
      menuButton.setAttribute("aria-label",expanded?"Open menu":"Close menu");
      nav.classList.toggle("open",!expanded);
    });
    nav.addEventListener("click",e => {if(e.target.closest("a"))close();});
    document.addEventListener("keydown",e => {if(e.key==="Escape")close();});
    document.addEventListener("click",e => {
      if(!nav.contains(e.target)&&!menuButton.contains(e.target))close();
    });
  }
  const year=document.getElementById("year");
  if(year)year.textContent=String(new Date().getFullYear());
  if("IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches){
    const observer=new IntersectionObserver(entries=>{
      for(const entry of entries){
        if(entry.isIntersecting){entry.target.classList.add("is-visible");observer.unobserve(entry.target);}
      }
    },{threshold:.06,rootMargin:"0px 0px -20px 0px"});
    document.querySelectorAll(".reveal").forEach(item=>observer.observe(item));
  }else{
    document.querySelectorAll(".reveal").forEach(item=>item.classList.add("is-visible"));
  }
})();