import {ComponentFixture, TestBed} from '@angular/core/testing';
import {button-testComponent} from "./button-test.component";
import {TranslateLoader, TranslateModule} from "@ngx-translate/core";
import {Observable, of} from "rxjs";

describe('ButtonTestComponent', () => {
  let fixture: ComponentFixture<ButtonTestComponent>;
  let component: ButtonTestComponent;

  beforeEach(() => {
    TestBed.configureTestingModule({
      declarations: [ButtonTestComponent],
      imports: [TranslateModule.forRoot({
        loader: {
          provide: TranslateLoader, useValue: {
            getTranslation(): Observable<Record<string, string>> {
              return of({});
            }
          }
        }
      })],
    }).compileComponents();

    fixture = TestBed.createComponent(ButtonTestComponent);
    component = fixture.componentInstance;
  });

  it('should create the component', () => {
    expect(component).toBeTruthy();
  });
});
