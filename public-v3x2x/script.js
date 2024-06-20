// For Making Header Responsive
const drawer_btn = document.querySelector(".drawer-btn");
const close_btn = document.querySelector(".close-btn");
const nav = document.querySelector(".nav");
const drawer = nav.querySelector(".drawer");
const blank = nav.querySelector(".blank");
const close = () => {
  nav.classList.remove("blur");
  drawer.classList.remove("drawer-visible");
};

drawer_btn.addEventListener("click", (e) => {
  nav.classList.add("blur");
  drawer.classList.add("drawer-visible");
});

close_btn.addEventListener("click", (e) => {
  close();
});

blank.addEventListener("click", (e) => {
  close();
});

Array.from(drawer.querySelectorAll("a")).forEach((element) => {
  element.addEventListener("click", () => {
    close();
  });
});
